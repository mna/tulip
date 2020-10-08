local tcheck = require 'tcheck'
local Mw = require 'web.pkg.csrf.Mw'

local M = {}

-- The csrf package registers a middleware that protects against CSRF
-- attacks. It is based on Go's gorilla CSRF package (https://github.com/gorilla/csrf),
-- itself based on Django and Ruby on Rails.
--
-- It uses an HMAC-authenticated cookie to store a cryptographically-secure CSRF token,
-- and each non-safe (e.g. POST, PUT, DELETE, etc.) http request must provide the
-- token either via a hidden input form field or a custom request header. The provided
-- token is masked with a unique per-request token to protect against the BREACH attack.
--
-- If the request is authenticated (i.e. a req.session_id field is present), that session
-- id is used as part of the HMAC authentication (but not present in the CSRF cookie), so
-- that a cookie from one session cannot be used to forge one for a different session.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  app:register_middleware('web.pkg.csrf', Mw.new(cfg))
end

return M
