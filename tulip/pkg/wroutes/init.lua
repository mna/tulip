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
--
-- Requires: the wmiddleware package.
--
-- Config:
--
-- * Array of tables: the configuration is an array of route tables
--   where each table can have the following fields:
--   * wmiddleware: array of string|function = the wmiddleware to apply
--     to this route
--   * handler: string|function = the final wmiddleware to apply to this
--     route
--   * pattern: string = the Lua pattern that the queue must match for this
--     route
--   * any other field on the route will be stored on the Request instance
--     under the routeargs field.
--
-- The wmiddleware handlers receive the message instance as
-- argument as well as a next function to call the next middleware.
-- The pattern does not have to be anchored, and if it
-- contains any captures, those are provided on the message object in the
-- queueargs field, as an array of values.
--
-- The configuration table can also have the following non-array field:
-- * not_found (function): handler to call if no route matches the message.
--   The default not found handler is a no-op (the message is not marked
--   as done).
--
-- Wmiddleware:
--
-- * tulip.pkg.wroutes
--
--   Routes the message to the matching route, or the not_found handler.
--
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
