local lu = require 'luaunit'
local App = require 'web.App'
local Request = require 'web.pkg.server.Request'
local Response = require 'web.pkg.server.Response'
local Stream = require 'test.Stream'

local function build_args(method, path)
  local stm = Stream.new(method, path)
  local req = Request.new(stm)
  local res = Response.new(stm)
  stm.request = req
  stm.response = res
  return req, res
end

local function app_config()
  return {
    routes = {
      {method = 'GET', pattern = '^/a(.*)', handler = function(_, res) res:write{status = 201} end},
      {method = 'GET', pattern = '^/b', handler = function(_, res) res:write{status = 202} end},
      {method = 'HEAD', pattern = '^/b', handler = function(_, res) res:write{status = 203} end},
      {method = 'POST', pattern = '^/c', handler = function(_, res) res:write{status = 204} end},
      {method = 'GET', pattern = '^/ab', handler = function(_, res) res:write{status = 205} end},
      {method = 'GET', pattern = '^/id', middleware = {'reqid'}, handler = function(_, res) res:write{status = 206} end},
      not_found = function(_, res) res.explicit = true; res:write{status = 404} end,
      no_such_method = function(_, res, ms) res.methods = ms; res:write{status = 405} end,
    },
    reqid = {},
  }
end

local M = {}

function M.test_mux()
  local app = App(app_config())
  app.main = function()
    local req, res = build_args('GET', '/abcd')
    app(req, res)
    lu.assertEquals(req.pathargs, {'bcd', n=1})
    lu.assertEquals(res.headers:get(':status'), '201')

    req, res = build_args('GET', '/bcd')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '202')

    -- no such method
    req, res = build_args('GET', '/cd')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '405')
    lu.assertEquals(res.methods, {'POST'})

    req, res = build_args('POST', '/cd')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '204')

    req, res = build_args('GET', '/d')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '404')
    lu.assertTrue(res.explicit)

    -- HEAD via GET
    req, res = build_args('HEAD', '/az')
    app(req, res)
    lu.assertEquals(req.pathargs, {'z', n=1})
    lu.assertEquals(res.headers:get(':status'), '201')

    -- explicit HEAD match
    req, res = build_args('HEAD', '/b')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '203')
  end
  app:run()
end

function M.test_mux_fallback_notfound()
  local cfg = app_config()
  cfg.routes.no_such_method = nil

  local app = App(cfg)
  app.main = function()
    local req, res = build_args('GET', '/cd')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '404')
  end
  app:run()
end

function M.test_mux_default_notfound()
  local cfg = app_config()
  cfg.routes.not_found = nil

  local app = App(cfg)
  app.main = function()
    local req, res = build_args('GET', '/d')
    app(req, res)
    lu.assertEquals(res.headers:get(':status'), '404')
    lu.assertNil(res.explicit)
  end
  app:run()
end

return M
