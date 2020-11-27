local Emw = {__name = 'web.handler.Emw'}
Emw.__index = Emw

function Emw:__call(req, res, nxt)
  local errh = self.error_handler
  self.handler(req, res, nxt, errh)
end

-- Emw implements a middleware with an error handler that is provided to
-- the handler as extra (4th) argument, so that when the middleware is
-- called with (req, res, nxt), it calls handler h with (req, res, nxt, errh).
--
-- As a convention, the error handler should receive (req, res, nxt, err),
-- that is, the actual error as 4th argument.
function Emw.new(h, errh)
  local o = {handler = h, error_handler = errh}
  return setmetatable(o, Emw)
end

return Emw
