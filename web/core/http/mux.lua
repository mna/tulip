local fn = require 'fn'

local Mux = {__name = 'web.core.http.Mux'}
Mux.__index = Mux

local function match(routes, path)
  local _, _, _, route = fn.any(function(_, route)
    return string.find(path, route.pattern)
  end, ipairs(routes))

  if route then
    return route, table.pack(string.match(path, route.pattern))
  end
  return nil
end

local function notfound(_, stm)
  stm.response:write{
    status = 404,
    body = 'not found',
    content_type = 'text/plain',
  }
end

function Mux:handle(srv, stm)
  local method = stm.request.method
  local path = stm.request.url.path

  local route, pathargs
  local routes = self.bymethod[method]
  if routes then
    route, pathargs = match(routes, path)
  end

  -- if no route did match, check if it's a HEAD and if so
  -- search in GET
  if not route and method == 'HEAD' then
    routes = self.bymethod['GET']
    if routes then
      route, pathargs = match(routes, path)
    end
  end
  if route then
    stm.request.pathargs = pathargs
    return route.handler(srv, stm)
  end

  -- trigger either the no_such_method or the not_found
  -- handler, if specified.
  if self.routes.no_such_method then
    -- look for matches with other methods
    local methods = {}
    for m, rs in pairs(self.bymethod) do
      if m == method then goto continue end
      if match(rs, path) then
        table.insert(methods, m)
      end
      ::continue::
    end
    if #methods > 0 then
      return self.routes.no_such_method(srv, stm, methods)
    end
  end
  local nf = self.routes.not_found or notfound
  return nf(srv, stm)
end

local M = {}

-- Creates a new request multiplexer that dispatches using the provided
-- routes table. That table holds the route patterns in the array part,
-- where each route is a table with the following fields:
-- * method (string): the http method to match against
-- * pattern (string): the Lua pattern that the path part of the request
--   must match.
-- * handler (function): the handler to call in case of match.
--
-- The handler has the usual lua-http signature - it receives the server
-- and the stream. The pattern does not have to be anchored, and if it
-- contains any captures, those are provided on the request object in the
-- pathargs field, as an array of values.
--
-- The routes table can also have the following non-array fields:
-- * no_such_method (function): handler to call if no route matches the
--   request, but only due to the http method. The not_found handler is
--   called if this field is not set. In addition to the usual server and
--   stream arguments, a 3rd table argument is passed, which is the array
--   of http methods supported for this path.
-- * not_found (function): handler to call if no route matches the request.
--   The default not found handler is called if this field is not set, which
--   returns 404 with a plain text body.
--
-- If the request is a HEAD and there is no route found, the Mux tries to
-- find and call a match for a GET and the same path before giving up.
function M.new(routes)
  local o = {routes = routes}
  setmetatable(o, Mux)

  -- index by method
  o.bymethod = fn.reduce(function(c, _, route)
    local t = c[route.method] or {}
    table.insert(t, route)
    c[route.method] = t
    return c
  end, {}, ipairs(routes))
  return o
end

return M
