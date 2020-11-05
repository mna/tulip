local tcheck = require 'tcheck'

local Mux = {__name = 'web.pkg.wroutes.Mux'}
Mux.__index = Mux

function Mux:handle(msg)
end

-- Creates a new multiplexer that dispatches using the provided
-- routes table. That table holds the route patterns in the array part,
-- where each route is a table with the following fields:
-- * pattern (string): the Lua pattern that the queue part of the message
--   must match.
-- * middleware (array): list of middleware functions to call.
--
-- The table should not be modified after the call.
--
-- The middleware handlers receive the message instance as
-- argument as well as a next function to call the next middleware.
-- The pattern does not have to be anchored, and if it
-- contains any captures, those are provided on the message object in the
-- pathargs field, as an array of values.
--
-- The routes table can also have the following non-array field:
-- * not_found (function): handler to call if no route matches the message.
--   The default not found handler is a no-op (the message is not
--   marked as done).
function Mux.new(routes)
  tcheck('table', routes)

  local o = {routes = routes}
  setmetatable(o, Mux)

  for i, route in ipairs(routes) do
    if (route.pattern or '') == '' then
      error(string.format('pattern missing at wroutes[%d]', i))
    elseif (not route.middleware) or (#route.middleware == 0) then
      error(string.format('handler missing at wroutes[%d]', i))
    end
  end
  return o
end

return Mux
