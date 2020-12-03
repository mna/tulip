local handler = require 'web.handler'
local lu = require 'luaunit'
local request = require 'http.request'
local xtest = require 'test.xtest'

local M = {}

function M.config_http()
  return {
    log = { level = 'd', file = 'account_http.out' },
    server = { host = 'localhost', port = 0 },
    routes = {
      {method = 'GET', pattern = '^/public',
        middleware = {'account:authz', handler.write{status = 204}}},
      {method = 'GET', pattern = '^/private', allow = {'*'},
        middleware = {'account:authz', handler.write{status = 204}}},
    },
    middleware = {
      handler.recover(function(_, res, err)
        local app = res.app
        app:log('d', {err = err})
        res:write{status = 500, body = tostring(err)}
      end),
      'routes',
    },
    urlenc = {},
    database = {
      connection_string = '',
      pool = {},
    },

    account = {
      auth_key = os.getenv('LUAWEB_ACCOUNTKEY'),
      session = {
        secure = false,
        same_site = 'none',
      },
    },
  }
end

local TO = 10

function M.test_over_http()
  xtest.withserver(function(port)
    local hdrs, res
    local req = request.new_from_uri(
      string.format('http://localhost:%d/', port))
    req.headers:upsert(':method', 'GET')

    req.headers:upsert(':path', '/public')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '204')

    req.headers:upsert(':path', '/private')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '401')
  end, 'test.account_mw', 'config_http')
end

return M
