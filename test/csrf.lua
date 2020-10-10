local crypto = require 'web.pkg.csrf.crypto'
local handler = require 'web.handler'
local lu = require 'luaunit'
local request = require 'http.request'
local xtest = require 'test.xtest'

local function set_session_id(req, _, nxt)
  if req.url.query.ssn then
    req.session_id = req.url.query.ssn
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

function M.config()
  return {
    log = { level = 'd', file = 'csrf_server.out' },
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
  }
end

function M.test_csrf()
  local TO = 10
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
    local cfg = M.config().csrf
    local raw = crypto.decode(cfg.auth_key,
      cfg.max_age,
      ck,
      'csrf',
      '-')
    lu.assertNotNil(raw)
    lu.assertEquals(#raw, 32)

    -- making a POST request should fail without sending the token
    req.headers:upsert(':method', 'POST')
    hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    body = res:get_body_as_string(TO)
    lu.assertEquals(body, 'Forbidden')
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
    lu.assertEquals(body, 'Forbidden')
    lu.assertEquals(hdrs:get(':status'), '403')
  end, 'test.csrf', 'config')
end

return M
