local tcheck = require 'tcheck'
local Mux = require 'tulip.pkg.routes.Mux'

local Mw = {__name = 'tulip.pkg.routes.Mw'}
Mw.__index = Mw

function Mw.new()
  local o = {}
  return setmetatable(o, Mw)
end

function Mw:__call(req, res, nxt)
  self.mux:handle(req, res)
  nxt()
end

local M = {
  requires = {
    'tulip.pkg.middleware',
  },
}

-- The routes package registers a route multiplexer where each
-- request is routed to a specific handler based on the method
-- and path, with optional route-specific middleware applied.
--
-- Requires: the middleware package.
--
-- Config:
--
-- * Array of tables: the configuration is an array of routes tables
--   where each table can have the following fields:
--   * middleware: array of string|function = the middleware to apply
--     to this route
--   * handler: string|function = the final middleware to apply to this
--     route
--   * method: string = the http method that matches this route
--   * pattern: string = the Lua pattern that the path must match for this
--     route
--   * any other field on the route will be stored on the Request instance
--     under the routeargs field.
--
-- The middleware handlers receive the Request and Response instances as
-- arguments as well as a next function to call the next middleware.
-- The pattern does not have to be anchored, and if it
-- contains any captures, those are provided on the Request object in the
-- pathargs field, as an array of values.
--
-- The configuration table can also have the following non-array fields:
-- * no_such_method (function): handler to call if no route matches the
--   request, but only due to the http method. The not_found handler is
--   called if this field is not set. In addition to the Request and
--   Response arguments, a 3rd table argument is passed, which is the
--   array of http methods supported for this path.
-- * not_found (function): handler to call if no route matches the request.
--   The default not found handler is called if this field is not set, which
--   returns 404 with a plain text body.
--
-- Middleware:
--
-- * tulip.pkg.routes
--
--   Routes the request to the matching route, or the not_found handler
--   (or no_such_method if it is set and applies to the request).
--   If the request is a HEAD and there is no route found, it tries to
--   find and call a match for a GET and the same path before giving up.
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  -- at this stage, only register an empty middleware - the mux
  -- instance it will delegate to will only be added in activate,
  -- when routes have been fully resolved.
  app:register_middleware('tulip.pkg.routes', Mw.new())
end

function M.activate(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  -- resolve all middleware strings to actual functions
  for _, route in ipairs(cfg) do
    local mws = route.middleware or {}
    if route.handler then
      table.insert(mws, route.handler)
    end
    app:resolve_middleware(mws)
    route.middleware = mws
  end
  local mw = app:lookup_middleware('tulip.pkg.routes')
  mw.mux = Mux.new(cfg)
end

return M
