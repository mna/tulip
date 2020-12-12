local handler = require 'tulip.handler'
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

-- The wmiddleware package enables app-level worker middleware (as opposed
-- to queue-specific worker middleware) in the
-- order specified in the configuration. This means that messages
-- will go through those middleware handlers in that order.
--
-- Config: array of string|function = the order of the middleware
-- to apply to worker messages.
--
-- Methods and Fields:
--
-- App(msg, nxt)
--
--   Sets up the __call metamethod on the App's metatable so
--   that it can be used as initial middleware.
--
--   > msg: table = the worker Message instance
--   > nxt: function|nil = the function that calls the next middleware
--
-- f = App:lookup_wmiddleware(name)
--
--   Returns the wmiddleware registered for that name, or nil if none.
--
--   > name: string = the name for the registered wmiddleware
--   < f: function = the registered wmiddleware
--
-- App:register_wmiddleware(name, mw)
--
--   Registers the wmiddleware mw for name. If there is already a registered
--   wmiddleware for name, throws an error.
--
--   > name: string = the name of the wmiddleware
--   > mw: function = middleware function (or callable table)
--
-- App:resolve_wmiddleware(mws)
--
--   Resolves the wmiddleware identified by a string in the array mws to
--   their actual function (or callable table).
--
--   > mws: array of string|function = the defined wmiddleware
--
-- App.wmiddleware: array of string|function
--
--   The list of wmiddleware to apply to worker messages. When the App is
--   called as initial middleware, it triggers that chain of middleware
--   next, in sequence.
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.wmiddleware = cfg

  local mt = getmetatable(app)
  mt.__call = app_call
end

function M.activate(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app:resolve_wmiddleware(app.wmiddleware)
end

return M
