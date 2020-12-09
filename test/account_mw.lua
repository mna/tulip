local cjson = require 'cjson'
local cqueues = require 'cqueues'
local handler = require 'tulip.handler'
local lu = require 'luaunit'
local neturl = require 'net.url'
local request = require 'http.request'
local xtest = require 'test.xtest'
local App = require 'tulip.App'

local function write_info(req, res)
  local acct = req.locals.account
  res:write{
    status = 200,
    content_type = 'application/json',
    body = {
      ssn_id = req.locals.session_id,
      acct_id = acct.id,
      groups = table.concat(acct.groups, ','),
    },
  }
end

local M = {}

function M.config_http()
  return {
    log = { level = 'd', file = 'account_http.out' },
    server = { host = 'localhost', port = 0 },
    routes = {
      {method = 'GET', pattern = '^/public',
        middleware = {'account:check_session', 'account:authz', handler.write{status = 204}}},
      {method = 'GET', pattern = '^/private', allow = {'*'},
        middleware = {'account:check_session', 'account:authz', write_info}},

      {method = 'POST', pattern = '^/signup',
        middleware = {'account:signup', handler.write{status = 204}}},
      {method = 'POST', pattern = '^/login',
        middleware = {'account:login', handler.write{status = 204}}},
      {method = 'GET', pattern = '^/logout',
        middleware = {'account:check_session', 'account:authz', 'account:logout', handler.write{status = 204}}},
      {method = 'POST', pattern = '^/delete',
        middleware = {'account:check_session', 'account:delete', handler.write{status = 204}}},

      {method = 'GET', pattern = '^/g1', allow = {'g1'}, deny = {'*'},
        middleware = {'account:check_session', 'account:authz', handler.write{status = 204}}},
      {method = 'GET', pattern = '^/verified', allow = {'@'},
        middleware = {'account:check_session', 'account:authz', handler.write{status = 204}}},
      {method = 'POST', pattern = '^/setpwd', allow = {'*'},
        middleware = {'account:check_session', 'account:authz', 'account:setpwd', handler.write{status = 204}}},

      {method = 'GET', pattern = '^/vemail/start',
        middleware = {'account:check_session', 'account:init_vemail', handler.write{status = 204}}},
      {method = 'GET', pattern = '^/vemail/end',
        middleware = {'account:vemail', handler.write{status = 204}}},

      {method = 'POST', pattern = '^/resetpwd/start',
        middleware = {'account:init_resetpwd', handler.write{status = 204}}},
      {method = 'POST', pattern = '^/resetpwd/end',
        middleware = {'account:resetpwd', handler.write{status = 204}}},

      {method = 'POST', pattern = '^/changeemail/start',
        middleware = {'account:check_session', 'account:init_changeemail', handler.write{status = 204}}},
      {method = 'GET', pattern = '^/changeemail/end',
        middleware = {'account:changeemail', handler.write{status = 204}}},
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
    json = {},
    token = {},
    mqueue = {
      default_max_age = 1,
      default_max_attempts = 2,
    },
    database = {
      connection_string = '',
      pool = {},
      migrations = {
        {
          package = 'test',
          after = {'tulip.pkg.account'};
          [[
          INSERT INTO tulip_pkg_account_groups
            (name)
          VALUES
            ('g1'), ('g2'), ('g3')
          ]],
        },
      },
    },

    account = {
      auth_key = os.getenv('TULIP_ACCOUNTKEY'),
      session = {
        secure = false,
        same_site = 'none',
      },
    },
  }
end

local TO = 10

function M.test_over_http()
  local app = App{
    mqueue = {},
    database = {connection_string = ''},
  }

  app.main = function()
    xtest.withserver(function(port)
      local hdrs, res
      local req = request.new_from_uri(
        string.format('http://localhost:%d/', port))

      assert(app:db(function(conn)
        assert(conn:exec[[
        DELETE FROM tulip_pkg_mqueue_pending
        ]])
        assert(conn:exec[[
        DELETE FROM tulip_pkg_mqueue_active
        ]])
        return true
      end))

      -- authz: no constraint
      hdrs, res = xtest.http_request(req, 'GET', '/public', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- authz: require authenticated
      hdrs, res = xtest.http_request(req, 'GET', '/private', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')

      -- logout: no-op when not logged in
      hdrs, res = xtest.http_request(req, 'GET', '/logout', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- init_vemail: fails without account
      hdrs, res = xtest.http_request(req, 'GET', '/vemail/start', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

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

      -- login: unknown email
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = 'nope@example.com', password = pwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')
      local ck = req.cookie_store:get('localhost', '/', 'ssn')
      lu.assertNil(ck)

      -- login: invalid password
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user1..'@example.com', password = pwd2}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')
      ck = req.cookie_store:get('localhost', '/', 'ssn')
      lu.assertNil(ck)
      local first_ssn_ck = ck

      -- login: valid, with user1
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user1..'@example.com', password = pwd1, rememberme = 't'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')
      ck = req.cookie_store:get('localhost', '/', 'ssn')
      lu.assertTrue(ck and ck ~= '')

      -- check_session: accessing private route returns logged-in info
      hdrs, res = xtest.http_request(req, 'GET', '/private', '', TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '200')
      local body = cjson.decode(res:get_body_as_string(TO))
      lu.assertEquals(#body.ssn_id, 44)
      lu.assertTrue(body.acct_id > 0)
      lu.assertNotEquals(body.ssn_id, ck)
      lu.assertEquals(body.groups, '')

      -- check_session/authz: cannot access g1 route (user has no group)
      hdrs, res = xtest.http_request(req, 'GET', '/g1', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '403')

      -- logout: from logged in
      hdrs, res = xtest.http_request(req, 'GET', '/logout', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')
      ck = req.cookie_store:get('localhost', '/', 'ssn')
      lu.assertNil(ck)

      -- accessing private now fails (not logged in)
      hdrs, res = xtest.http_request(req, 'GET', '/private', '', TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')

      -- login with user 2
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user2..'@example.com', password = pwd2, rememberme = 't'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')
      ck = req.cookie_store:get('localhost', '/', 'ssn')
      lu.assertTrue(ck and ck ~= '')
      lu.assertNotEquals(ck, first_ssn_ck)

      -- check_session: accessing private route returns logged-in info
      hdrs, res = xtest.http_request(req, 'GET', '/private', '', TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '200')
      body = cjson.decode(res:get_body_as_string(TO))
      lu.assertEquals(#body.ssn_id, 44)
      lu.assertTrue(body.acct_id > 0)
      lu.assertNotEquals(body.ssn_id, ck)
      lu.assertEquals(body.groups, 'g1,g2')

      -- check_session/authz: can access g1 route
      hdrs, res = xtest.http_request(req, 'GET', '/g1', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- check_session/authz: cannot access verified route
      hdrs, res = xtest.http_request(req, 'GET', '/verified', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '403')

      local newpwd2 = tostring(cqueues.monotime())
      -- setpwd with invalid password confirmation
      hdrs, res = xtest.http_request(req, 'POST', '/setpwd',
        neturl.buildQuery({
          email = user2..'@example.com', old_password = pwd2,
          new_password = newpwd2, new_password2 = 'nope',
        }), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- setpwd with invalid original password
      hdrs, res = xtest.http_request(req, 'POST', '/setpwd',
        neturl.buildQuery({email = user2..'@example.com', old_password = 'nope', new_password = newpwd2}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- setpwd: valid
      hdrs, res = xtest.http_request(req, 'POST', '/setpwd',
        neturl.buildQuery({
          email = user2..'@example.com', old_password = pwd2,
          new_password = newpwd2, new_password2 = newpwd2,
        }), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- init_vemail: enqueue token
      hdrs, res = xtest.http_request(req, 'GET', '/vemail/start', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- get the enqueued message
      local msgs, err = app:mqueue({queue = 'sendemail'})
      lu.assertNil(err)
      lu.assertEquals(#msgs, 1)
      local msg = msgs[1]
      assert(app:db(function(conn)
        assert(msg:done(conn))
        return true
      end))

      -- vemail: pass invalid token
      hdrs, res = xtest.http_request(req, 'GET', {
        '/vemail/end';
        t = 'nope',
        e = msg.payload.email,
      }, nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- vemail: pass valid token
      hdrs, res = xtest.http_request(req, 'GET',
        {
          '/vemail/end';
          t = msg.payload.encoded_token,
          e = msg.payload.email,
        }, nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- check_session/authz: can now access verified route
      hdrs, res = xtest.http_request(req, 'GET', '/verified', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- logout
      hdrs, res = xtest.http_request(req, 'GET', '/logout', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- init_resetpwd: returns 200 if email is not found
      hdrs, res = xtest.http_request(req, 'POST', '/resetpwd/start',
        neturl.buildQuery({email = 'nope@example.com'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '200')

      -- there is no enqueued message
      msgs, err = app:mqueue({queue = 'sendemail'})
      lu.assertNil(err)
      lu.assertEquals(#msgs, 0)

      -- init_resetpwd: valid
      hdrs, res = xtest.http_request(req, 'POST', '/resetpwd/start',
        neturl.buildQuery({email = user1..'@example.com'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- get the enqueued message
      msgs, err = app:mqueue({queue = 'sendemail'})
      lu.assertNil(err)
      lu.assertEquals(#msgs, 1)
      msg = msgs[1]
      assert(app:db(function(conn)
        assert(msg:done(conn))
        return true
      end))

      -- resetpwd: invalid token
      hdrs, res = xtest.http_request(req, 'POST', '/resetpwd/end',
        neturl.buildQuery({
          e = user1..'@example.com',
          t = 'nope',
          new_password = 'abcd',
        }), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- resetpwd: valid token
      local newpwd1 = tostring(cqueues.monotime())
      hdrs, res = xtest.http_request(req, 'POST', '/resetpwd/end',
        neturl.buildQuery({
          e = user1..'@example.com',
          t = msg.payload.encoded_token,
          new_password = newpwd1,
          new_password2 = newpwd1,
        }), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- init_changeemail: no account
      hdrs, res = xtest.http_request(req, 'POST', '/changeemail/start',
        neturl.buildQuery({new_email = 'nope@example.com'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- login with user 1
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user1..'@example.com', password = newpwd1, rememberme = 't'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- init_changeemail: conflicting email
      hdrs, res = xtest.http_request(req, 'POST', '/changeemail/start',
        neturl.buildQuery({new_email = user2..'@example.com'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      local user3 = tostring(cqueues.monotime())
      -- init_changeemail: valid
      hdrs, res = xtest.http_request(req, 'POST', '/changeemail/start',
        neturl.buildQuery({new_email = user3..'@example.com'}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- changeemail: invalid token
      hdrs, res = xtest.http_request(req, 'GET', {
        '/changeemail/end',
        t = 'nope',
        oe = user1..'@example.com',
        ne = user3..'@example.com',
      }, '', TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- get the enqueued message
      msgs, err = app:mqueue({queue = 'sendemail'})
      lu.assertNil(err)
      lu.assertEquals(#msgs, 1)
      msg = msgs[1]
      assert(app:db(function(conn)
        assert(msg:done(conn))
        return true
      end))

      -- changeemail: valid token
      hdrs, res = xtest.http_request(req, 'GET', {
        '/changeemail/end',
        t = msg.payload.encoded_token,
        oe = msg.payload.old_email,
        ne = msg.payload.new_email,
      }, '', TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- logout
      hdrs, res = xtest.http_request(req, 'GET', '/logout', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- authz: private now fails, not authenticated
      hdrs, res = xtest.http_request(req, 'GET', '/private', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')

      -- login: old email address fails
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user1..'@example.com', password = newpwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')

      -- delete: no account
      hdrs, res = xtest.http_request(req, 'POST', '/delete',
        neturl.buildQuery({password = newpwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- login: success with user3
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user3..'@example.com', password = newpwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- delete: invalid password
      hdrs, res = xtest.http_request(req, 'POST', '/delete',
        neturl.buildQuery({password = pwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '400')

      -- delete: valid password
      hdrs, res = xtest.http_request(req, 'POST', '/delete',
        neturl.buildQuery({password = newpwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- authz: private fails, account deleted
      hdrs, res = xtest.http_request(req, 'GET', '/private', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')

      -- login: fails with user3 (deleted)
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user3..'@example.com', password = newpwd1}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '401')

      -- login: success with user2
      hdrs, res = xtest.http_request(req, 'POST', '/login',
        neturl.buildQuery({email = user2..'@example.com', password = newpwd2}), TO, {
          ['content-type'] = 'application/x-www-form-urlencoded',
        })
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')

      -- authz: can access /g1 (has this group)
      hdrs, res = xtest.http_request(req, 'GET', '/g1', nil, TO)
      lu.assertNotNil(hdrs and res)
      lu.assertEquals(hdrs:get(':status'), '204')
    end, 'test.account_mw', 'config_http')
  end
  app:run()
end

return M
