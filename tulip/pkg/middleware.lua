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

-- The middleware package enables app-level middleware (as opposed
-- to route-specific middleware) in the
-- order specified in the configuration. This means that requests
-- will go through those middleware handlers in that order.
--
-- Config: array of string|function = the order of the middleware
-- to apply to web requests.
--
-- Methods and Fields:
--
-- App(req, res, nxt)
--
--   Sets up the __call metamethod on the App's metatable so
--   that it can be used as initial middleware.
--
--   > req: table = the http Request instance
--   > res: table = the http Response instance
--   > nxt: function|nil = the function that calls the next middleware
--
-- v = App:lookup_middleware(name)
--
--   Returns the middleware registered for that name, or nil if none.
--
--   > name: string = the name for the registered middleware
--   < v: array = the registered middleware
--
-- App:register_middleware(name, mw)
--
--   Registers the middleware mw for name. If there is already a registered
--   middleware for name, throws an error.
--
--   > name: string = the name of the middleware
--   > mw: function = middleware function (or callable table)
--
-- App:resolve_middleware(mws)
--
--   Resolves the middleware identified by a string in the array mws to
--   their actual function (or callable table).
--
--   > mws: array of string|function = the defined middleware
--
-- App.middleware: array of string|function
--
--   The list of middleware to apply to web requests. When the App is
--   called as initial middleware, it triggers that chain of middleware
--   next, in sequence.
--
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
