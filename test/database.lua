local cqueues = require 'cqueues'
local lu = require 'luaunit'
local xpgsql = require 'xpgsql'
local xtest = require 'test.xtest'
local App = require 'web.App'

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
        application_name = ''
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
    database = {connection_string = ''}
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

function M.test_database_pool()
  local app = App{
    database = {
      connection_string = '',
      pool = {
        max_idle = 2,
        max_open = 3,
        idle_timeout = 2,
        life_timeout = 4,
      },
    }
  }

  app.main = function()
    -- initial conn is created to run the migrations
    lu.assertEquals(count_conns(), 1)

    local c1 = app:db()
    lu.assertEquals(count_conns(), 1)
    local c2 = app:db()
    lu.assertEquals(count_conns(), 2)
    local c3 = app:db()
    lu.assertEquals(count_conns(), 3)
    lu.assertErrorMsgContains('too many', function()
      app:db()
    end)
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

function M.test_migrations_order()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = '',
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
      DROP TABLE IF EXISTS web_pkg_database_migrations
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
    'web.pkg.database', 'a', 'b', 'd', 'c',
  })
end

function M.test_migrations_minimal()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = '',
      migrations = {
        {package = 'a'; function() end},
        {package = 'b', after = {'a'}; function() end},
      },
    }
  }

  -- drop the migration table to ensure all migrations are run
  assert(app:db(function(conn)
    assert(conn:exec[[
      DROP TABLE IF EXISTS web_pkg_database_migrations
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
    'web.pkg.database', 'a', 'b',
  })
end

function M.test_migrations_order_circular()
  local app = App{
    log = {level = 'd', file = '/dev/null'},
    database = {
      connection_string = '',
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
      DROP TABLE IF EXISTS web_pkg_database_migrations
    ]])
    return true
  end))

  app.main = function() end
  lu.assertErrorMsgContains('circular dependency', app.run, app)
end

return M
