local lu = require 'luaunit'
local xtest = require 'test.xtest'
local App = require 'web.App'

local M = {}

function M:setup()
  xtest.extrasetup(self)
end

function M:teardown()
  xtest.extrateardown(self)
end

function M:beforeAll()
  local ok, cleanup, err = xtest.newdb('', xtest.mockcron)
  if not ok then cleanup() end
  assert(ok, err)

  self.cleanup = cleanup
end

function M:afterAll()
  self.cleanup()
end

function M.test_cron_missing_dep()
  local ok, err = pcall(App, {
    database = {connection_string = ''},
    cron = {},
  })
  lu.assertFalse(ok)
  lu.assertStrContains(err, 'no message queue registered')

  ok, err = pcall(App, {
    mqueue = {},
    cron = {},
  })
  lu.assertFalse(ok)
  lu.assertStrContains(err, 'no database registered')
end

function M.test_cron()
  local app = App{
    database = {connection_string = ''},
    mqueue = {},
    cron = {
      allowed_jobs = {'a', 'b', 'c'},
      jobs = {
        a = {
          schedule = '* 1 * * *',
          payload = {x = 1},
        },
      },
    },
  }

  app.main = function()
    -- schedule job b
    local ok, err = app:schedule('b', nil, '* 2 * * *')
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- schedule job c
    ok, err = app:schedule('c', nil, {
      schedule = '* 3 * * *',
      payload = function()
        return {x=2}
      end,
    })
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- schedule job d fails (invalid job)
    ok, err = app:schedule('d', nil, '* 4 * * *')
    lu.assertNil(ok)
    lu.assertStrContains(err, 'is invalid')

    -- unschedule job b
    ok, err = app:schedule('b')
    lu.assertNil(err)
    lu.assertTrue(ok)

    -- cannot test much more as cron is mocked in test database
  end
  app:run()
end

return M
