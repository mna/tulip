local handler = require 'web.handler'
local lu = require 'luaunit'
local request = require 'http.request'
local xtest = require 'test.xtest'

local M = {}

function M.config()
  return {
    server = { host = '127.0.0.1', port = 0 },
    routes = {
      {method = 'GET', pattern = '^/', handler = handler.write{status = 204}},
    },
    middleware = { 'csrf', 'routes' },
    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
    },
  }
end

function M.test_csrf()
  local TO = 10
  xtest.withserver(function(port)
    local req = request.new_from_uri(
      string.format('http://localhost:%d/', port))
    req.headers:upsert(':method', 'GET')
    local hdrs, res = req:go(TO)

    lu.assertNotNil(hdrs)
    lu.assertNotNil(res)
    local body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')
  end, 'test.csrf', 'config')
end

return M
