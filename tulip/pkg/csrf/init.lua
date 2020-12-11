local tcheck = require 'tcheck'
local Mw = require 'tulip.pkg.csrf.Mw'

local M = {
  requires = {
    'tulip.pkg.middleware',
  },
}

-- The csrf package registers a middleware that protects against CSRF
-- attacks.
--
-- Config:
--
-- * auth_key: string = authentication key to sign the cookie
-- * cookie_name: string = name of the cookie holding the signed token
--   (default: 'csrf')
-- * http_only: boolean = http-only flag of the cookie (default: true)
-- * secure: boolean = secure flag of the cookie (default: true)
-- * max_age: number = max age in seconds of the cookie (default: 12 hours)
-- * domain: string = domain of the cookie (default: not set)
-- * path: string = path of the cookie (default: not set)
-- * same_site: string = same-site flag of the cookie (default: 'lax')
-- * request_header: string = request header to look for the csrf token
--   (default: 'x-csrf-token')
-- * input_name: string = form field to look for the csrf token (default:
--   '_csrf_token')
-- TODO: use error handler and error as 4th arg, as for account package
-- * fail_handler: function = middleware function to call on error (default:
--   reply with 403, body contains error message)
-- * trusted_origins: array of strings = trusted origins for https requests
--
-- Middleware:
--
-- * tulip.pkg.csrf
--
-- Protects against CSRF attacks. It is based on Go's gorilla CSRF package
-- (https://github.com/gorilla/csrf), itself based on Django and Ruby on
-- Rails.
--
-- It uses an HMAC-authenticated cookie to store a cryptographically-secure CSRF token,
-- and each non-safe (e.g. POST, PUT, DELETE, etc.) http request must provide the
-- token either via a hidden input form field or a custom request header. The provided
-- token is masked with a unique per-request token to protect against the BREACH attack.
--
-- If the request is authenticated (i.e. a req.locals.session_id field is present), that session
-- id is used as part of the HMAC authentication (but not present in the CSRF cookie), so
-- that a cookie from one session cannot be used to forge one for a different session.
--
-- The generated token is stored in req.locals.csrf_token and the name of the form field
-- that should send the token is stored in req.locals.csrf_input_name so that e.g. templates
-- can generate proper forms.
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app:register_middleware('tulip.pkg.csrf', Mw.new(cfg))
end

return M
