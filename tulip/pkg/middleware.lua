local handler = require 'tulip.handler'
local tcheck = require 'tcheck'

local function app_call(app, req, res, nxt)
  if not app.middleware then
    if nxt then nxt() end
    return
  end
  handler.chain_middleware(app.middleware, req, res, nxt)
end

local M = {
  app = {
    register_middleware = function(self, name, mw)
      tcheck({'*', 'string', 'table|function'}, self, name, mw)
      self:_register('_middleware', name, mw)
    end,

    lookup_middleware = function(self, name)
      tcheck({'*', 'string'}, self, name)
      return self:_lookup('_middleware', name)
    end,

    resolve_middleware = function(self, mws)
      tcheck({'*', 'table'}, self, mws)
      self:_resolve('_middleware', mws)
    end,
  },
}

-- The middleware package enables app-level middleware in the
-- order specified in the configuration. This means that requests
-- will go through those middleware handlers in that order.
-- It also sets up the __call metamethod on the App's metatable so
-- that it can be used as initial middleware.
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.middleware = cfg

  local mt = getmetatable(app)
  mt.__call = app_call
end

function M.activate(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app:resolve_middleware(app.middleware)
end

return M
