local fn = require 'fn'
local middleware = require 'web.pkg.account.middleware'
local migrations = require 'web.pkg.account.migrations'
local tcheck = require 'tcheck'
local xerror = require 'web.xerror'
local xtable = require 'web.xtable'
local Account = require 'web.pkg.account.Account'

local function create_account(app, email, raw_pwd, groups, conn)
  tcheck({'*', 'string', 'string|nil', 'table|nil', 'table|nil'}, app, email, raw_pwd, groups, conn)

  local close = not conn
  conn = conn or app:db()
  return conn:with(close, function()
    return Account.new(email, raw_pwd, groups, conn)
  end)
end

local function get_account(app, v, raw_pwd, conn)
  local types = tcheck({'*', 'string|number', 'string|nil', 'table|nil'}, app, v, raw_pwd, conn)

  local close = not conn
  conn = conn or app:db()
  return conn:with(close, function()
    if types[2] == 'string' then
      return Account.by_email(v, raw_pwd, conn)
    else
      return Account.by_id(v, raw_pwd, conn)
    end
  end)
end

local M = {}

local MWPREFIX = 'web.pkg.account'

-- table of middleware name to config key (to be merged with the auth_key)
-- and default error handler. If config key is nil, no config is provided
-- to the middleware.
local MWCONFIG = {
  signup = {config = nil, handler = nil},
  login = {config = 'session', handler = nil},
  check_session = {config = 'session', handler = nil},
  logout = {config = 'session', handler = nil},
  delete = {config = 'session', handler = nil},
  init_vemail = {config = 'verify_email', handler = nil},
  vemail = {config = 'verify_email', handler = nil},
  setpwd = {config = nil, handler = nil},
  init_resetpwd = {config = 'reset_password', handler = nil},
  resetpwd = {config = 'reset_password', handler = nil},
  init_changeemail = {config = 'change_email', handler = nil},
  changeemail = {config = 'change_email', handler = nil},
  authz = {config = nil, handler = nil},
}

local MWDEFAULTS = {
  session = {
    token_type = 'session',
    token_max_age = 30 * 24 * 3600,
    cookie_name = 'ssn',
    cookie_max_age = 30 * 24 * 3600,
    secure = true,
    http_only = true,
    same_site = 'lax',
  },
  verify_email = {
    token_type = 'vemail',
    token_max_age = 2 * 24 * 3600,
    queue_name = 'sendemail',
    queue_max_age = 30,
    max_attempts = 3,
  },
  reset_password = {
    token_type = 'resetpwd',
    token_max_age = 2 * 24 * 3600,
    queue_name = 'sendemail',
    queue_max_age = 30,
    max_attempts = 3,
  },
  change_email = {
    token_type = 'changeemail',
    token_max_age = 2 * 24 * 3600,
    queue_name = 'sendemail',
    queue_max_age = 30,
    max_attempts = 3,
  },
}

-- The account package handles account creation and management, so
-- that new accounts can be created, login and logout supported,
-- sessions created via a cookie, etc. It also supports the email
-- verification, password reset and email change workflows.
--
-- It registers two methods on the App instance and a number of methods are
-- also available on the Account instance returned by App:create_account or
-- App:account. It also registers a number of middleware, described below.
--
-- Requires: database, token and mqueue packages (and a body decoder, typically
-- urlenc).
--
-- Config:
--  * auth_key: string = authentication key for the all signed tokens.
--  * session: table = session-related configuration used by middleware:
--    * token_type: string = type of the session token (default: 'session')
--    * token_max_age: number = max age in seconds of the token (default:
--      30 days).
--    * cookie_name: string = name of the cookie holding the signed token
--      (default: 'ssn')
--    * cookie_max_age: number = max age in seconds of the session cookie
--      when "remember me" is requested (default: 30 days)
--    * domain: string = domain of the session cookie (default: not set)
--    * path: string = path of the session cookie (default: not set)
--    * secure: boolean = secure flag of the session cookie (default: true)
--    * http_only: boolean = http-only flag of the session cookie (default:
--      true)
--    * same_site: string = same-site flag of the session cookie (default:
--      'lax')
--  * verify_email,
--    reset_password,
--    change_email: tables = configuration of middleware related to those:
--    * token_type: string = type of the generated token (default:
--      'vemail', 'resetpwd' and 'changeemail', respectively)
--    * token_max_age: number = max age in seconds of the token (default:
--      2 days)
--    * queue_name: string = name of the message queue where the message
--      to send the email is posted (default: 'sendemail')
--    * queue_max_age: number = max age in seconds to process the queue
--      message (default: 30)
--    * max_attempts: number = max attempts to process the queue message
--      successfully before being moved to dead (default: 3)
--    * payload: table = arbitrary table to post as part of the queue message,
--      will be combined with the actual dynamic payload (default: nil)
--  * error_handlers: table = table of error handlers, one for each
--    available middleware - each value is a function that should expect
--    (req, res, nxt, err) as arguments:
--    * signup = by default, 400 if EINVAL or throws the error
--    * login = by default, 401 if EINVAL or throws the error
--    * check_session = by default throws the error
--    * logout = by default throws the error
--    * delete = by default, 400 if EINVAL or throws the error
--    * init_vemail = by default, 400 if EINVAL or throws the error
--    * vemail = by default, 400 if EINVAL or throws the error
--    * setpwd = by default, 400 if EINVAL or throws the error
--    * init_resetpwd = by default, 200 if EINVAL or throws the error
--    * resetpwd = by default, 400 if EINVAL or throws the error
--    * init_changeemail = by default, 400 if EINVAL or throws the error
--    * changeemail = by default, 400 if EINVAL or throws the error
--    * authz = by default, 403
--
-- Methods:
--
-- acct, err = App:create_account(email, raw_pwd[, groups[, conn]])
--
--   Creates a new Account.
--
--   > email: string = the email address
--   > raw_pwd: string = the raw (unhashed) password
--   > conn: connection|nil = optional database connection to use
--
--   < acct: Account = the created Account instance
--   < err: string|nil = error message if acct is nil
--
-- acct, err = App:account(v[, raw_pwd[, conn]])
--
--   Lookups an existing Account.
--
--   > v: string|number = either the email address or account id
--   > raw_pwd: string|nil = if provided, validates that it corresponds
--     to the password of this account.
--   > conn: connection|nil = optional database connection to use
--
--   < acct: Account = the corresponding Account instance, nil if
--     raw_pwd is provided but doesn't match the account's password.
--   < err: string|nil = error message if acct is nil
--
-- ok, err = Account:delete(conn)
--
--   Deletes the account.
--
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:verify_email(conn)
--
--   Marks the account's email as verified. Note that this doesn't
--   generate nor validates a random token, nor does it send an
--   email for verification, it only sets the verified timestamp.
--
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:change_pwd(new_pwd, conn)
--
--   Updates the account's password to new_pwd.
--
--   > new_pwd: string = the new raw password
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:change_email(new_email, conn)
--
--   Updates the account's email address to new_email, and marks
--   it immediately as verified - as it should only be called once
--   that email address has been verified.
--
--   > new_email: string = the new email address
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:change_groups(add, rm, conn)
--
--   Adds and/or removes the account from the groups.
--
--   > add: string|table|nil = the group(s) to add the account to.
--   > rm: string|table|nil = the group(s) to remove the account from.
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- Middleware:
--
-- * web.pkg.account:signup
--
--   Handles the signup workflow (POST of a form). On success,
--   the created account is stored in req.locals.account.
--
--   > email: string = form field with the email address
--   > password: string = form field with the raw password
--   > password2: string|nil = optional form field with the raw password again
--
-- * web.pkg.account:login
--
--   Handles the login workflow (POST of a form). On success,
--   the logged-in account is stored under req.locals.account and
--   a session is initiated, with its id stored under req.locals.session_id
--   and a session cookie stored in the response's headers.
--
--   > email: string = form field with the email address
--   > password: string = form field with the raw password
--   > rememberme: boolean = indicates if the session should be persisted
--
-- * web.pkg.account:check_session
--
--   Decodes the request's session cookie if present and valid, and sets
--   the req.locals.session_id and req.locals.account fields. Note that
--   it does not deny access if invalid or absent, use the authz middleware
--   to that effect.
--
-- * web.pkg.account:logout
--
--   Handles the logout workflow, which deletes the session cookie and token
--   and unsets the req.locals.session_id and req.locals.account fields.
--
-- * web.pkg.account:delete
--
--   Handles the delete account workflow (POST of a form). On success,
--   the account is deleted.
--
--   > password: string = the raw password of the acount, must be validated
--     to proceed with account deletion.
--
-- * web.pkg.account:init_vemail
--
--   Initiates the verify email workflow, typically after a successful signup
--   middleware. It generates a single-use token and enqueues a job to send
--   an email message to the account. Can also be set as middleware to a
--   "resend verify email" endpoint.
--
-- * web.pkg.account:vemail
--
--   Handles the verify email workflow. Checks that the token is valid
--   and if so marks the email as verified.
--
--   > t: string = the token, stored in a query string parameter.
--   > e: string = the email to verify, stored in a query string parameter.
--
-- * web.pkg.account:setpwd
--
--   Handles the update password workflow (POST of a form). Must be
--   logged-in (i.e. the Account must be stored in req.locals.account).
--
--   > old_password: string = the old (raw) password
--   > new_password: string = the new (raw) password
--   > new_password2: string|nil = optional confirmation of the new (raw) password
--
-- * web.pkg.account:init_resetpwd
--
--   Initiates the reset password workflow, typically from a request on the
--   login form when the user forgets their password. It generates a single-use
--   token and sends an email message to the account.
--
--   > email: string = the email to which the reset token should be sent.
--
-- * web.pkg.account:resetpwd
--
--   Handles the reset password workflow (POST of form). Checks the the
--   token is valid and if so, updates the password to the new one.
--
--   > t: string = the token, either as query string or in a form field
--   > e: string = the email used to reset the password, either as query
--     string or in a form field
--   > new_password: string = the new (raw) password
--   > new_password2: string|nil = optional confirmation of the new (raw) password
--
-- * web.pkg.account:init_changeemail
--
--   Initiates the change email workflow. It generates a single-use
--   token and sends an email message to the specified new email
--   address.
--
--   > new_email: string = the new email to which the reset token
--   should be sent.
--
-- * web.pkg.account:changeemail
--
--   Handles the change email workflow. Checks that the token is valid
--   and if so updates the corresponding account's email address to
--   the new one.
--
--   > t: string = the token, stored in a query string parameter.
--   > oe: string = the old email, as query string
--   > ne: string = the new email, as query string
--
-- * web.pkg.account:authz
--
--   Handles authorization based on the routeargs of the request, renders
--   either 403 if user is authenticated but doesn't have required group
--   membership, 401 if user is not authenticated, or 302 Found and redirect to
--   login page. Supports the following pseudo-groups:
--
--   - '?': authorize/deny anyone, authenticated or not
--   - '*': authorize/deny any authenticated user
--   - '@': authorize/deny any verified authenticated user
--
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.create_account = create_account
  app.account = get_account

  local db = app.config.database
  if not db then
    xerror.throw('no database registered')
  end
  db.migrations = db.migrations or {}
  table.insert(db.migrations, {
    package = 'web.pkg.account';
    table.unpack(migrations)
  })

  -- register the middleware
  for k, v in pairs(MWCONFIG) do
    local errh = cfg.error_handlers and cfg.error_handlers[k] or v.handler
    local mwcfg = v.config and xtable.merge({auth_key = cfg.auth_key}, MWDEFAULTS[v.config], cfg[v.config])
    app:register_middleware(MWPREFIX .. ':' .. k, fn.partialtrail(middleware[k], errh, mwcfg))
  end
end

return M
