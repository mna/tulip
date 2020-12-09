local tcheck = require 'tcheck'
local Mux = require 'tulip.pkg.wroutes.Mux'

local Mw = {__name = 'tulip.pkg.wroutes.Mw'}
Mw.__index = Mw

function Mw.new()
  local o = {}
  return setmetatable(o, Mw)
end

function Mw:__call(msg, nxt)
  self.mux:handle(msg)
  nxt()
end

local M = {
  requires = {
    'tulip.pkg.wmiddleware',
  },
}

-- The wroutes package registers a route multiplexer where each
-- message is routed to a specific handler based on the queue
-- name, with optional route-specific middleware applied.
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  -- at this stage, only register an empty wmiddleware - the mux
  -- instance it will delegate to will only be added in activate,
  -- when wroutes have been fully resolved.
  app:register_wmiddleware('tulip.pkg.wroutes', Mw.new())
end

function M.activate(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  -- resolve all wmiddleware strings to actual functions
  for _, route in ipairs(cfg) do
    local mws = route.wmiddleware or {}
    if route.handler then
      table.insert(mws, route.handler)
    end
    app:resolve_wmiddleware(mws)
    route.wmiddleware = mws
  end
  local mw = app:lookup_wmiddleware('tulip.pkg.wroutes')
  mw.mux = Mux.new(cfg)
end

return M
