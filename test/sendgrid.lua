local lu = require 'luaunit'

local App = require 'tulip.App'

local M = {}

function M.test_sendgrid()
  local app = App{
    sendgrid = {
      api_key = os.getenv('TULIP_SENDGRIDKEY'),
      from = os.getenv('TULIP_TEST_FROMEMAIL'),
      timeout = 10,
    },
  }

  -- valid email
  local ok, err = app:email{
    to = {os.getenv('TULIP_TEST_TOEMAIL')},
    subject = 'tulip test',
    body = 'Hello!',
  }
  lu.assertNil(err)
  lu.assertTrue(ok)

  -- invalid request - missing recipient
  ok, err = app:email{
    subject = 'FAIL tulip test',
    body = 'FAIL!',
  }
  lu.assertStrContains(err, '.to')
  lu.assertTrue(not ok)
end

return M
