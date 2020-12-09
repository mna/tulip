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
