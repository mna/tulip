local cqueues = require 'cqueues'
local lu = require 'luaunit'
local stdlib = require 'posix.stdlib'
local xerror = require 'tulip.xerror'
local xpgsql = require 'xpgsql'
local xtest = require 'test.xtest'
local App = require 'tulip.App'

local function count_conns()
  local c = assert(xpgsql.connect(''))
  return assert(c:with(true, function()
    local res = assert(c:query[[
      SELECT
        COUNT(*)
      FROM
        pg_stat_activity
      WHERE
        datname = current_database() AND
        pid != pg_backend_pid() AND
        application_name = 'test'
    ]])
    return tonumber(res[1][1])
  end))
end

local function pid(conn)
  return assert(conn:with(false, function()
    local res = assert(conn:query[[
      SELECT pg_backend_pid()
    ]])
    return tonumber(res[1][1])
  end))
end

local M = {}

function M:setup()
  xtest.extrasetup(self)
end

function M:teardown()
  xtest.extrateardown(self)
end

function M:beforeAll()
  local ok, cleanup, err = xtest.newdb('')
  if not ok then cleanup() end
  assert(ok, err)

  self.cleanup = cleanup
end

function M:afterAll()
  self.cleanup()
end

function M.test_database_nopool()
  local app = App{
    database = {connection_string = 'application_name=test'}
  }

  app.main = function()
    lu.assertEquals(count_conns(), 0)

    local c1 = app:db()
    lu.assertEquals(count_conns(), 1)
    c1:close()
    lu.assertEquals(count_conns(), 0)

    local got = app:db(function(c)
      return pid(c)
    end)
    lu.assertTrue(got > 0)
    lu.assertEquals(count_conns(), 0)
  end
  app:run()
  lu.assertEquals(count_conns(), 0)
end

function M.test_database_fail_connect()
  local app = App{
    database = {connection_string = 'application_name=test'}
  }

  app.main = function()
    local olddb = os.getenv('PGDATABASE')
    stdlib.setenv('PGDATABASE', 'no_such_database')

    local ok, err = pcall(function()
      local cx, err = app:db()
      lu.assertNil(err)
      local res; res, err = cx:query('SELECT 1')
      lu.assertNil(res)
      lu.assertStrContains(tostring(err), 'database "no_such_database" does not exist')
      lu.assertTrue(xerror.is(err, 'EIO'))

      cx, err = app:db(function() end)
      lu.assertNil(cx)
      lu.assertStrContains(tostring(err), 'database "no_such_database" does not exist')
      lu.assertTrue(xerror.is(err, 'EIO'))
    end)
    stdlib.setenv('PGDATABASE', olddb)
    assert(ok, err)
  end
  app:run()
end

function M.test_database_pool()
  local app = App{
    database = {
      migrations_connection_string = 'application_name=test',
      connection_string = 'application_name=test',
      pool = {
        max_idle = 2,
        max_open = 3,
        idle_timeout = 2,
        life_timeout = 4,
      },
    }
  }

  app.main = function()
    -- no initial conn created for the migrations because a distinct connection
    -- string is used.
    lu.assertEquals(count_conns(), 0)

    local c1 = app:db()
    lu.assertEquals(count_conns(), 1)
    local c2 = app:db()
    lu.assertEquals(count_conns(), 2)
    local c3 = app:db()
    lu.assertEquals(count_conns(), 3)
    local cx, err = app:db(function() end)
    lu.assertNil(cx)
    lu.assertStrContains(tostring(err), 'too many')
    lu.assertTrue(xerror.is(err, 'EDB'))
    lu.assertEquals(count_conns(), 3)

    -- call db without function, should fail too, on first use
    cx, err = app:db()
    lu.assertNil(err)
    local res; res, err = cx:query('SELECT 1')
    lu.assertNil(res)
    lu.assertStrContains(tostring(err), 'too many')
    lu.assertTrue(xerror.is(err, 'EDB'))
    lu.assertEquals(count_conns(), 3)

    -- closing c1, c2 and c3
    c1:close(); c2:close(); c3:close()
    -- only 2 remain open (max 2 idle)
    lu.assertEquals(count_conns(), 2)

    -- get one, should be from the pool
    local c4 = app:db()
    lu.assertEquals(count_conns(), 2)

    -- sleep a bit and get one, it should clear the oldest one
    -- that has been idle too long.
    cqueues.sleep(2)
    local pid4 = pid(c4)
    local c4birth = c4._birth
    lu.assertTrue(pid4 > 0)
    c4:close()
    lu.assertEquals(count_conns(), 2)

    cqueues.sleep(1)
    local c5 = app:db()
    lu.assertEquals(count_conns(), 1)
    -- it kept the same as pid4 (the other had been idle too long)
    -- unless c4 has been alive to long itself :( need to check some
    -- internals to protect against this flaky failure.
    local pid5 = pid(c5)
    local alive = os.difftime(os.time(), c4birth)
    if alive > app.config.database.pool.life_timeout then
      lu.assertNotEquals(pid5, pid4)
    else
      lu.assertEquals(pid5, pid4)
    end
    c5:close()

    -- exceed its lifetime timeout
    c5._birth = os.time() - app.config.database.pool.life_timeout - 1
    local c6 = app:db()
    lu.assertEquals(count_conns(), 1)
    local pid6 = pid(c6)
    lu.assertTrue(pid6 > 0)
    lu.assertNotEquals(pid5, pid6)
    c6:close()

    -- test passing a function to app:db
    app:db(function(c)
      local pidx = pid(c)
      lu.assertEquals(pid6, pidx)
      return true
    end)
    lu.assertEquals(count_conns(), 1)
  end
  app:run()
  lu.assertEquals(count_conns(), 0)
end

function M.test_database_pool_release()
  local app = App{
    database = {
      connection_string = 'application_name=test',
      pool = {
        release_connection = function(c)
          assert(c:query('SELECT pg_advisory_unlock_all()'))
        end,
      },
    }
  }

  app.main = function()
    local c1 = app:db()
    local c2 = app:db()
    lu.assertEquals(count_conns(), 2)

    -- acquire the lock using c1
    assert(c1:query('SELECT pg_advisory_lock(1)'))
    -- try to acquire it using c2, timeout after a bit
    assert(c2:exec("SET lock_timeout = 100"))
    local ok, err = c2:query('SELECT pg_advisory_lock(1)')
    lu.assertStrContains(err, 'lock timeout')
    lu.assertNil(ok)

    -- closing c1 releases it to the pool and releases the lock
    c1:close()

    -- c2 can now acquire the lock
    assert(c2:query('SELECT pg_advisory_lock(1)'))
    c2:close()
  end

  app:run()
  lu.assertEquals(count_conns(), 0)
end

function M.test_database_pool_release_throws()
  local throw_now = false
  local app = App{
    database = {
      connection_string = 'application_name=test',
      pool = {
        release_connection = function()
          if throw_now then
            error('release failed')
          end
        end,
      },
    }
  }

  app.main = function()
    local c1 = app:db()
    throw_now = true
    lu.assertErrorMsgContains('release failed', function() c1:close() end)
  end

  app:run()
  lu.assertEquals(count_conns(), 0)
end

function M.test_migrations_order()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = 'application_name=test',
      migrations = {
        {package = 'a'; function() end},
        {package = 'b', after = {'a'}; function() end},
        {package = 'c', after = {'a', 'd'}; function() end},
        {package = 'd', after = {'b'}; function() end},
      },
    }
  }

  -- drop the migration table to ensure all migrations are run
  assert(app:db(function(conn)
    assert(conn:exec[[
      DROP TABLE IF EXISTS tulip_pkg_database_migrations
    ]])
    return true
  end))

  -- register a logger to record the order of packages
  local order = {}
  app:register_logger('test', function(t)
    if t.migration then
      local mig = string.match(t.migration, '^[^:]+')
      table.insert(order, mig)
    end
  end)

  app.main = function() end
  app:run()

  lu.assertEquals(order, {
    'tulip.pkg.database', 'a', 'b', 'd', 'c',
  })
end

function M.test_migrations_check_fail()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = 'application_name=test',
      migrations = {
        check_only = true,
        check_timeout = 1;
        {package = 'a'; function() end},
        {package = 'b', after = {'a'}; function() end},
      },
    }
  }

  -- drop the migration table to ensure no migrations exist
  assert(app:db(function(conn)
    assert(conn:exec[[
      DROP TABLE IF EXISTS tulip_pkg_database_migrations
    ]])
    return true
  end))

  app.main = function() return true end
  lu.assertErrorMsgContains('timeout', function() assert(app:run()) end)
end

function M.test_migrations_minimal()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = 'application_name=test',
      migrations = {
        {package = 'a'; function() end},
        {package = 'b', after = {'a'}; function() end},
      },
    }
  }

  -- drop the migration table to ensure all migrations are run
  assert(app:db(function(conn)
    assert(conn:exec[[
      DROP TABLE IF EXISTS tulip_pkg_database_migrations
    ]])
    return true
  end))

  -- register a logger to record the order of packages
  local order = {}
  app:register_logger('test', function(t)
    if t.migration then
      local mig = string.match(t.migration, '^[^:]+')
      table.insert(order, mig)
    end
  end)

  app.main = function() return true end
  assert(app:run())

  lu.assertEquals(order, {
    'tulip.pkg.database', 'a', 'b',
  })

  -- configure the App to check migrations only
  app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = 'application_name=test',
      migrations = {
        check_only = true,
        check_timeout = 1;
        {package = 'a'; function() end},
        {package = 'b', after = {'a'}; function() end},
      },
    }
  }
  app.main = function() return true end
  assert(app:run())
end

function M.test_migrations_order_circular()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = 'application_name=test',
      migrations = {
        {package = 'a'; function() end},
        {package = 'b', after = {'a', 'd'}; function() end},
        {package = 'c', after = {'b'}; function() end},
        {package = 'd', after = {'c'}; function() end},
      },
    }
  }

  -- drop the migration table to ensure all migrations are run
  assert(app:db(function(conn)
    assert(conn:exec[[
      DROP TABLE IF EXISTS tulip_pkg_database_migrations
    ]])
    return true
  end))

  app.main = function() end
  lu.assertErrorMsgContains('circular dependency', app.run, app)
end

return M
