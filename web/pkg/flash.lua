local tcheck = require 'tcheck'

local function flash_method(req, t)

end

local function load_flashes(req)
end

local function make_write_headers(req, res)
  local oldfn = res._write_headers
  return function(self, hdrs, eos, deadline)
    local flashes = req.locals._flash
    -- TODO: create/update or remove cookie based on flashes
    return oldfn(self, hdrs, eos, deadline)
  end
end

local function flash_middleware(req, res, nxt)
  -- install the modified res method, to write the flash messages'
  -- cookie before sending the response.
  res._write_headers = make_write_headers(req, res)

  -- load existing flashes
  req.locals._flash = load_flashes(req)

  nxt()
end

local M = {
  requires = {
    'web.pkg.middleware',
  },
}

-- The flash package adds flash message support to the App. Flash messages
-- are (short) feedback messages that are generated in one request, but only
-- used in a subsequent request (e.g. following an account creation, after
-- a redirect to the login page, the "account created, please login" message
-- could be displayed). To that end, the flash messages are stored in a
-- session cookie by the middleware registered with this package. Note that
-- it must be enabled in order for flash messages to work.
--
-- Requires: the middleware package.
--
-- Config: none
--
-- Methods:
--
-- v, err = Request:flash([t])
--
--   Adds a flash message, or retrieves all flash messages. Once retrieved,
--   the flash messages are "consumed" and removed for the next request. Flash
--   messages are stored in req.locals._flash until the end of the request
--   (where they are stored in the cookie), but should never be accessed
--   directly there, use this method instead.
--
--   > t: table|string = the message to add, will be url-encoded in the cookie.
--   < v: boolean|table = if a message to add is passed as argument, returns
--     a boolean indicating success, otherwise returns an array of flash
--     messages, which are either a table or a string.
--   < err: string|nil = if v is falsy, the error message.
--
-- Middleware:
--
-- * web.pkg.flash
--
--   Must be added before any handler that writes the response, so that the
--   flash messages get stored in a cookie (or the cookie gets deleted if
--   there are no messages).
--
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app:register_middleware('web.pkg.flash', flash_middleware)
end

return M
