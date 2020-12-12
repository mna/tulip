local fn = require 'fn'
local handler = require 'tulip.handler'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'

local function match(routes, s)
  local _, _, _, route = fn.any(function(_, route)
    return string.find(s, route.pattern)
  end, ipairs(routes))

  if route then
    return route, table.pack(string.match(s, route.pattern))
  end
end

local Mux = {__name = 'tulip.pkg.wroutes.Mux'}
Mux.__index = Mux

function Mux:handle(msg)
  local queue = msg.queue
  local route, queueargs = match(self.routes, queue)

  if route then
    msg.queueargs = queueargs
    handler.chain_wmiddleware(route.wmiddleware, msg)
    return
  end
  local nf = self.routes.not_found
  if nf then nf(msg) end
end

-- Creates a new multiplexer that dispatches using the provided
-- routes table. That table holds the route patterns in the array part,
-- where each route is a table with the following fields:
-- * pattern (string): the Lua pattern that the queue part of the message
--   must match.
-- * wmiddleware (array): list of wmiddleware functions to call.
--
-- The table should not be modified after the call.
--
-- The middleware handlers receive the message instance as
-- argument as well as a next function to call the next middleware.
-- The pattern does not have to be anchored, and if it
-- contains any captures, those are provided on the message object in the
-- queueargs field, as an array of values.
--
-- The routes table can also have the following non-array field:
-- * not_found (function): handler to call if no route matches the message.
--   The default not found handler is a no-op (the message is not
--   marked as done).
function Mux.new(routes)
  tcheck('table', routes)

  for i, route in ipairs(routes) do
    if (route.pattern or '') == '' then
      xerror.throw('pattern missing at wroutes[%d]', i)
    elseif (not route.wmiddleware) or (#route.wmiddleware == 0) then
      xerror.throw('handler missing at wroutes[%d]', i)
    end
  end

  local o = {routes = routes}
  return setmetatable(o, Mux)
end

return Mux
