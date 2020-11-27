local Emw = {__name = 'web.handler.Emw'}
Emw.__index = Emw

function Emw:__call(req, res, nxt)
  local hs = self.error_handlers
  self.handler(req, res, nxt, hs and table.unpack(hs, 1, hs.n))
end

-- Emw implements a middleware with one or many error handler(s) that are
-- provided to the handler as extra (4th, 5th, etc.) arguments, so that
-- when the middleware is called with (req, res, nxt), it calls handler
-- h with (req, res, nxt, errh1, errh2, ...).
--
-- As a convention, the error handler should expect (req, res, nxt, err)
-- when called, that is, the actual error as 4th argument.
function Emw.new(h, ...)
  local o = {handler = h, error_handlers = table.pack(...)}
  return setmetatable(o, Emw)
end

return Emw
