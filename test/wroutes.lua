local lu = require 'luaunit'
local App = require 'tulip.App'

local function mw(msg, nxt)
  msg.mw = true
  nxt()
end

local function app_config()
  return {
    wroutes = {
      {pattern = '^a(.*)', handler = function(msg) msg.n = 1 end},
      {pattern = '^b', handler = function(msg) msg.n = 2 end},
      {pattern = '^c', wmiddleware = {mw}, handler = function(msg) msg.n = 3 end},
      not_found = function(msg) msg.explicit = true end,
    },
    wmiddleware = {'wroutes'},
  }
end

local M = {}

function M.test_mux()
  local app = App(app_config())
  app.main = function()
    local msg = {queue = 'abc'}
    app(msg)
    lu.assertEquals(msg.pathargs, {'bc', n=1})
    lu.assertEquals(msg.n, 1)
    lu.assertNil(msg.mw)

    msg = {queue = 'b'}
    app(msg)
    lu.assertEquals(msg.n, 2)
    lu.assertNil(msg.mw)

    msg = {queue = 'c'}
    app(msg)
    lu.assertEquals(msg.n, 3)
    lu.assertTrue(msg.mw)

    msg = {queue = 'd'}
    app(msg)
    lu.assertTrue(msg.explicit)
    lu.assertNil(msg.n)
    lu.assertNil(msg.mw)
  end
  app:run()
end

function M.test_mux_default_notfound()
  local cfg = app_config()
  cfg.wroutes.not_found = nil

  local app = App(cfg)
  app.main = function()
    local msg = {queue = 'x'}
    app(msg)
    lu.assertNil(msg.n)
    lu.assertNil(msg.explicit)
  end
  app:run()
end

return M
