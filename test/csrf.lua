local crypto = require 'web.crypto'
local handler = require 'web.handler'
local lu = require 'luaunit'
local neturl = require 'net.url'
local process = require 'process'
local request = require 'http.request'
local xtest = require 'test.xtest'

local function set_session_id(req, _, nxt)
  if req.url.query.ssn then
    req.locals.session_id = req.url.query.ssn
  end
  nxt()
end

local function write_token(req, res)
  res:write{
    status = 200,
    body = req.locals.csrf_token,
    content_type = 'text/plain',
  }
end

local M = {}

function M.config_http()
  return {
    log = { level = 'd', file = 'csrf_http.out' },
    server = { host = 'localhost', port = 0 },
    routes = {
      {method = 'GET', pattern = '^/', handler = write_token},
      {method = 'POST', pattern = '^/', handler = handler.write{status = 204}},
    },
    middleware = { set_session_id, 'csrf', 'routes' },
    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
      max_age = 3600,
      secure = false,
      same_site = 'none', -- required for the cookie_store to work
    },
    urlenc = {},
  }
end

function M.config_https()
  return {
    log = { level = 'd', file = 'csrf_https.out' },
    server = {
      host = 'localhost',
      port = 0,
      tls = {
        required = true,
        protocol = 'TLS',
        certificate_path = 'run/certs/fullchain.pem',
        private_key_path = 'run/certs/privkey.pem',
      },
    },
    routes = {
      {method = 'GET', pattern = '^/', handler = write_token},
      {method = 'POST', pattern = '^/', handler = handler.write{status = 204}},
    },
    middleware = { set_session_id, 'csrf', 'routes' },
    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
      max_age = 3600,
      same_site = 'none', -- required for the cookie_store to work
      trusted_origins = {
        'ok.localhost',
      },
    },
    urlenc = {},
  }
end

function M.config_expiry()
  return {
    log = { level = 'd', file = 'csrf_expiry.out' },
    server = { host = 'localhost', port = 0 },
    routes = {
      {method = 'GET', pattern = '^/', handler = write_token},
      {method = 'POST', pattern = '^/', handler = handler.write{status = 204}},
    },
    middleware = { 'csrf', 'routes' },
    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
      max_age = 1,
      secure = false,
      same_site = 'none', -- required for the cookie_store to work
    },
  }
end

local TO = 10

function M.test_csrf_over_https()
  xtest.withserver(function(port)
    local req = request.new_from_uri(
      string.format('https://localhost:%d/', port))
    req.headers:upsert(':method', 'GET')

    local hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    local body = res:get_body_as_string(TO)
    lu.assertTrue(body and body ~= '')
    lu.assertEquals(hdrs:get(':status'), '200')
    lu.assertStrIContains(hdrs:get('vary'), 'cookie')
    local ck = req.cookie_store:get('localhost', '/', 'csrf')
    lu.assertTrue(ck and ck ~= '')
    lu.assertNotEquals(ck, body) -- different because body token is masked

    local good_tok = body

    -- making a POST request with the token in the header should fail due to no referer
    req.headers:upsert(':method', 'POST')
    req.headers:upsert('x-csrf-token', good_tok)
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertStrContains(body, 'no referer')
    lu.assertEquals(hdrs:get(':status'), '403')

    -- making a POST request with the token and a referer from a different domain fails
    req.headers:upsert(':method', 'POST')
    req.headers:upsert('referer', 'http://example.com/')
    req.headers:upsert('x-csrf-token', good_tok)
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertStrContains(body, 'invalid referer')
    lu.assertEquals(hdrs:get(':status'), '403')

    -- POST request with the token and the exact domain as referer
    req.headers:upsert('referer', 'https://localhost/ok')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')

    -- POST request with the token and a non-trusted subdomain as referer
    req.headers:upsert('referer', 'https://notok.localhost/')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertStrContains(body, 'invalid referer')
    lu.assertEquals(hdrs:get(':status'), '403')

    -- POST request with the token and a trusted subdomain as referer
    req.headers:upsert('referer', 'https://ok.localhost/')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')
  end, 'test.csrf', 'config_https')
end

function M.test_csrf_over_http()
  xtest.withserver(function(port)
    local req = request.new_from_uri(
      string.format('http://localhost:%d/', port))
    req.headers:upsert(':method', 'GET')

    local hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    local body = res:get_body_as_string(TO)
    lu.assertTrue(body and body ~= '')
    lu.assertEquals(hdrs:get(':status'), '200')
    lu.assertStrIContains(hdrs:get('vary'), 'cookie')
    local ck = req.cookie_store:get('localhost', '/', 'csrf')
    lu.assertTrue(ck and ck ~= '')
    lu.assertNotEquals(ck, body) -- different because body token is masked

    local good_tok = body

    -- should be able to properly decode the cookie value
    local cfg = M.config_http().csrf
    local b64 = crypto.decode(cfg.auth_key,
      cfg.max_age,
      ck,
      'csrf',
      '-')
    lu.assertNotNil(b64)
    lu.assertEquals(#b64, 44)

    -- making a POST request should fail without sending the token
    req.headers:upsert(':method', 'POST')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertStrContains(body, 'Forbidden')
    lu.assertEquals(hdrs:get(':status'), '403')

    -- making a POST request with the token in the header should succeed
    req.headers:upsert('x-csrf-token', good_tok)
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')

    -- making a POST request with an invalid token in the header should fail
    req.headers:upsert('x-csrf-token', 'abcd')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(hdrs:get(':status'), '403')
    lu.assertStrContains(body, 'Forbidden')

    -- making another GET request returns a different token due to the mask
    req.headers:upsert(':method', 'GET')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(hdrs:get(':status'), '200')
    lu.assertNotEquals(good_tok, body)

    local good_tok2 = body

    -- this new good_tok2 works too
    req.headers:upsert('x-csrf-token', good_tok2)
    req.headers:upsert(':method', 'POST')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')

    -- the old good_tok is good too, and works in the form field
    req.headers:delete('x-csrf-token')
    req.headers:upsert(':method', 'POST')
    req.headers:upsert('content-type', 'application/x-www-form-urlencoded')
    req:set_body(neturl.buildQuery({_csrf_token = good_tok}))
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')

    -- the canonical token in the cookie is still the same
    local ck2 = req.cookie_store:get('localhost', '/', 'csrf')
    lu.assertEquals(ck, ck2)

    -- POSTing with a new session id causes the generation of a new cookie token,
    -- so the request fails despite having what was a good token
    req.headers:upsert('x-csrf-token', good_tok)
    req.headers:upsert(':method', 'POST')
    req.headers:upsert(':path', '/?ssn=abc')
    req.headers:delete('content-type')
    req:set_body('')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertStrContains(body, 'Forbidden')
    lu.assertEquals(hdrs:get(':status'), '403')

    -- the canonical token in the cookie has changed
    local ck3 = req.cookie_store:get('localhost', '/', 'csrf')
    lu.assertNotEquals(ck, ck3)

    -- making another GET request returns a new valid token
    req.headers:upsert(':method', 'GET')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(hdrs:get(':status'), '200')

    local good_tok3 = body

    -- and this new token made for requests with the session works
    req.headers:upsert('x-csrf-token', good_tok3)
    req.headers:upsert(':method', 'POST')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')
  end, 'test.csrf', 'config_http')
end

function M.test_csrf_expiry()
  xtest.withserver(function(port)
    -- make a GET request to get a valid token
    local req = request.new_from_uri(
      string.format('http://localhost:%d/', port))
    req.headers:upsert(':method', 'GET')

    local hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    local body = res:get_body_as_string(TO)
    lu.assertTrue(body and body ~= '')
    lu.assertEquals(hdrs:get(':status'), '200')

    -- sleep for a bit to let it expire
    process.sleep(2)
    local expired_tok = body

    -- make a POST request with the token
    req.headers:upsert(':method', 'POST')
    req.headers:upsert('x-csrf-token', expired_tok)
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertStrContains(body, 'Forbidden')
    lu.assertEquals(hdrs:get(':status'), '403')
  end, 'test.csrf', 'config_expiry')
end

return M
