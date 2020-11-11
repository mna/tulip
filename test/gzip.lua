local lu = require 'luaunit'
local zlib = require 'http.zlib'
local App = require 'web.App'
local Request = require 'web.pkg.server.Request'
local Response = require 'web.pkg.server.Response'
local Stream = require 'test.Stream'

local M = {}

function M.test_request()
  local app = App{
    server = {},
    middleware = {'gzip', function(_, res)
      res:write{body = 'hello'}
    end},
    gzip = {},
  }

  app.main = function()
    local newreqres = function(method, path, accept)
      local stm = Stream.new(method, path)
      local req = Request.new(stm, 5)
      local res = Response.new(stm, 5)
      stm.request, stm.response = req, res
      req.app, res.app = app, app
      if accept then
        req.headers:upsert('accept-encoding', 'gzip')
      end
      return req, res
    end

    -- call without accepting gzip
    local req, res = newreqres('GET', '/', false)
    app(req, res)
    res.stream:assertWritten({
      [':status'] = '200',
      ['content-length'] = '5',
      ['content-encoding'] = '',
      ['transfer-encoding'] = '',
      ['vary'] = 'Accept-Encoding',
    }, 'hello', true)

    -- call with accepting gzip
    local decompress = zlib.inflate()
    req, res = newreqres('GET', '/', true)
    app(req, res)
    res.stream:assertWritten({
      [':status'] = '200',
      ['content-length'] = '',
      ['content-encoding'] = 'gzip',
      ['transfer-encoding'] = 'chunked',
      ['vary'] = 'Accept-Encoding',
    }, nil, true)
    lu.assertEquals(decompress(res.stream._written.body, true), 'hello')
  end
  app:run()
end

return M
