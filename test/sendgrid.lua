local lu = require 'luaunit'

local App = require 'web.App'

local M = {}

function M.test_sendgrid()
  local app = App{
    sendgrid = {
      api_key = os.getenv('LUAWEB_SENDGRIDKEY'),
      from = os.getenv('LUAWEB_TEST_FROMEMAIL'),
      timeout = 10,
    },
  }

  -- valid email
  local ok, err = app:email{
    to = {os.getenv('LUAWEB_TEST_TOEMAIL')},
    subject = 'luaweb test',
    body = 'Hello!',
  }
  lu.assertNil(err)
  lu.assertTrue(ok)

  -- invalid request - missing recipient
  ok, err = app:email{
    subject = 'FAIL luaweb test',
    body = 'FAIL!',
  }
  lu.assertStrContains(err, '.to')
  lu.assertTrue(not ok)
end

return M
