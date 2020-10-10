local crypto = require 'web.pkg.csrf.crypto'
local handler = require 'web.handler'
local lu = require 'luaunit'
local request = require 'http.request'
local xtest = require 'test.xtest'

local M = {}

function M.config()
  return {
    server = { host = 'localhost', port = 0 },
    routes = {
      {method = 'GET', pattern = '^/', handler = handler.write{status = 204}},
    },
    middleware = { 'csrf', 'routes' },
    csrf = {
      auth_key = os.getenv('LUAWEB_CSRFKEY'),
      max_age = 3600,
      secure = false,
      same_site = 'none', -- required for the cookie_store to work
    },
  }
end

function M.test_csrf_returns_a_valid_cookie()
  local TO = 10
  xtest.withserver(function(port)
    local req = request.new_from_uri(
        string.format('http://localhost:%d/', port))
    req.headers:upsert(':method', 'GET')

    local hdrs, res = req:go(TO)
    lu.assertNotNil(hdrs and res)

    local body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '204')
    lu.assertStrIContains(hdrs:get('vary'), 'cookie')
    local ck = req.cookie_store:get('localhost', '/', 'csrf')
    lu.assertTrue(ck and ck ~= '')

    -- should be able to properly decode the cookie value
    local cfg = M.config().csrf
    local raw = crypto.decode(cfg.auth_key,
      cfg.max_age,
      ck,
      'csrf',
      '-')
    lu.assertNotNil(raw)
    lu.assertEquals(#raw, 32)
  end, 'test.csrf', 'config')
end

return M
