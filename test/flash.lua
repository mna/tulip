local lu = require 'luaunit'
local request = require 'http.request'
local xtest = require 'test.xtest'

local M = {}

function M.config_http()
  return {
    log = {level = 'd', file = 'flash_http.out'},
    server = {host = 'localhost', port = 0},
    middleware = {'flash', function(req, res)
      if req.url.path == '/1' then
        req:flash('a', {x='b'})
      elseif req.url.path == '/2' then
        req:flash({y='c'})
      end
      res:write{
        content_type = 'application/json',
        body = req.locals.flash,
      }
    end},
    flash = {
      secure = false,
      same_site = 'none', -- required for the cookie_store to work
    },
    json = {},
  }
end

local TO = 10

function M.test_flash()
  xtest.withserver(function(port)
    local req = request.new_from_uri(
      string.format('http://localhost:%d/', port))

    local hdrs, res = xtest.http_request(req, 'GET', '/', nil, TO)
    lu.assertNotNil(hdrs and res)
    local body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '200')
    local ck = req.cookie_store:get('localhost', '/', 'flash')
    lu.assertNil(ck)

    -- write some messages
    hdrs, res = xtest.http_request(req, 'GET', '/1', nil, TO)
    lu.assertNotNil(hdrs and res)
    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '')
    lu.assertEquals(hdrs:get(':status'), '200')
    ck = req.cookie_store:get('localhost', '/', 'flash')
    lu.assertTrue(ck and ck ~= '')

    -- write some new messages
    hdrs, res = xtest.http_request(req, 'GET', '/2', nil, TO)
    lu.assertNotNil(hdrs and res)
    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '["a",{"x":"b"}]')
    lu.assertEquals(hdrs:get(':status'), '200')
    ck = req.cookie_store:get('localhost', '/', 'flash')
    lu.assertTrue(ck and ck ~= '')

    -- no new messages
    hdrs, res = xtest.http_request(req, 'GET', '/', nil, TO)
    lu.assertNotNil(hdrs and res)
    body = res:get_body_as_string(TO)
    lu.assertEquals(body, '[{"y":"c"}]')
    lu.assertEquals(hdrs:get(':status'), '200')
    ck = req.cookie_store:get('localhost', '/', 'flash')
    lu.assertNil(ck)
  end, 'test.flash', 'config_http')
end

return M
