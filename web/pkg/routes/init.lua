local tcheck = require 'tcheck'
local Mux = require 'web.pkg.routes.Mux'

local Mw = {__name = 'web.pkg.routes.Mw'}
Mw.__index = Mw

function Mw.new()
  local o = {}
  setmetatable(o, Mw)
  return o
end

function Mw:__call(req, res, nxt)
  self.mux:handle(req, res)
  nxt()
end

local M = {}

-- The routes package registers a route multiplexer where each
-- request is routed to a specific handler based on the method
-- and path, with optional middleware applied.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  -- at this stage, only register an empty middleware - the mux
  -- instance it will delegate to will only be added in activate,
  -- when routes have been fully resolved.
  app:register_middleware('web.pkg.routes', Mw.new())
end

function M.activate(app)
  tcheck('web.App', app)

  local cfg = app.config.routes
  -- resolve all middleware strings to actual functions
  for _, route in ipairs(cfg) do
    local mws = route.middleware or {}
    if route.handler then
      table.insert(mws, route.handler)
    end
    app:resolve_middleware(mws)
    route.middleware = mws
  end
  local mw = app:lookup_middleware('web.pkg.routes')
  mw.mux = Mux.new(cfg)
end

return M
