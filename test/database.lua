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
        pid != pg_backend_pid()
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
    database = {
      connection_string = '',
    }
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
    lu.assertEquals(count_conns(), 0)

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

    -- sleep a bit, get and release one, should be from the pool
    cqueues.sleep(1)
    local c4 = app:db()
    lu.assertEquals(count_conns(), 2)

    -- sleep again a bit and get one, it should clear the oldest one
    -- that has been idle too long.
    cqueues.sleep(2)
    local pid4 = pid(c4)
    lu.assertTrue(pid4 > 0)
    c4:close()
    lu.assertEquals(count_conns(), 2)

    local c5 = app:db()
    lu.assertEquals(count_conns(), 1)
    local pid5 = pid(c5)
    lu.assertEquals(pid5, pid4)
    c5:close()

    -- at this point the only connection is at least 3 seconds old,
    -- sleep again a bit to exceed its lifetime timeout
    cqueues.sleep(2)
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

return M
