local handler = require 'web.handler'
local tcheck = require 'tcheck'

local function app_call(app, msg, nxt)
  if not app.wmiddleware then
    if nxt then nxt() end
    return
  end
  handler.chain_wmiddleware(app.wmiddleware, msg, nxt)
end

local M = {
  app = {
    register_wmiddleware = function(self, name, mw)
      tcheck({'*', 'string', 'table|function'}, self, name, mw)
      self:_register('_wmiddleware', name, mw)
    end,

    lookup_wmiddleware = function(self, name)
      tcheck({'*', 'string'}, self, name)
      return self:_lookup('_wmiddleware', name)
    end,

    resolve_wmiddleware = function(self, mws)
      tcheck({'*', 'table'}, self, mws)
      self:_resolve('_wmiddleware', mws)
    end,
  }
}

-- The wmiddleware package enables app-level worker middleware in the
-- order specified in the configuration. This means that messages
-- will go through those middleware handlers in that order.
-- It also sets up the __call metamethod on the App's metatable so
-- that it can be used as initial wmiddleware.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.wmiddleware = cfg

  local mt = getmetatable(app)
  mt.__call = app_call
end

function M.activate(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app:resolve_wmiddleware(app.wmiddleware)
end

return M
