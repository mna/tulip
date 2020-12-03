local handler = require 'web.handler'
local lu = require 'luaunit'
local neturl = require 'net.url'
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
      {method = 'POST', pattern = '^/signup',
        middleware = {'account:authz', 'account:signup', handler.write{status = 204}}},
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

    -- authz: no constraint
    hdrs, res = xtest.http_request(req, 'GET', '/public', nil, TO)
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '204')

    -- authz: require authenticated
    hdrs, res = xtest.http_request(req, 'GET', '/private', nil, TO)
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '401')

    local user1, pwd1 = tostring(os.time()), 'test1234'
    -- signup: create account
    hdrs, res = xtest.http_request(req, 'POST', '/signup',
      neturl.buildQuery({email = user1..'@example.com', password = pwd1}), TO, {
        ['content-type'] = 'application/x-www-form-urlencoded',
      })
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '204')
  end, 'test.account_mw', 'config_http')
end

return M
