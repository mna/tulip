local cqueues = require 'cqueues'
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
      migrations = {
        {
          package = 'test';
          [[
          INSERT INTO web_pkg_account_groups
            (name)
          VALUES
            ('g1'), ('g2'), ('g3')
          ]],
        },
      },
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

    local user1, pwd1 = tostring(cqueues.monotime()), 'atest1234'
    -- signup: create account
    hdrs, res = xtest.http_request(req, 'POST', '/signup',
      neturl.buildQuery({email = user1..'@example.com', password = pwd1}), TO, {
        ['content-type'] = 'application/x-www-form-urlencoded',
      })
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '204')

    -- signup: create duplicate account
    hdrs, res = xtest.http_request(req, 'POST', '/signup',
      neturl.buildQuery({email = user1..'@example.com', password = tostring(os.time())}), TO, {
        ['content-type'] = 'application/x-www-form-urlencoded',
      })
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '409')

    local user2, pwd2 = tostring(cqueues.monotime()), 'btest1234'
    -- signup: create account with invalid password confirmation
    hdrs, res = xtest.http_request(req, 'POST', '/signup',
      neturl.buildQuery({email = user2..'@example.com', password = pwd2, password2 = pwd1}), TO, {
        ['content-type'] = 'application/x-www-form-urlencoded',
      })
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '400')

    -- signup: create account with password confirmation and some groups
    hdrs, res = xtest.http_request(req, 'POST', '/signup',
      neturl.buildQuery({email = user2..'@example.com', password = pwd2, password2 = pwd2, groups = 'g1, g2'}), TO, {
        ['content-type'] = 'application/x-www-form-urlencoded',
      })
    lu.assertNotNil(hdrs and res)
    lu.assertEquals(hdrs:get(':status'), '204')
  end, 'test.account_mw', 'config_http')
end

return M
