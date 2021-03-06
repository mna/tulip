local fn = require 'fn'
local handler = require 'tulip.handler'
local middleware = require 'tulip.pkg.account.middleware'
local migrations = require 'tulip.pkg.account.migrations'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local xtable = require 'tulip.xtable'
local Account = require 'tulip.pkg.account.Account'

local function create_account(app, email, raw_pwd, groups, conn)
  tcheck({'*', 'string', 'string|nil', 'table|nil', 'table|nil'}, app, email, raw_pwd, groups, conn)

  local close = not conn
  if not conn then
    local err; conn, err = app:db()
    if not conn then
      return nil, err
    end
  end
  return conn:with(close, function()
    return Account.new(email, raw_pwd, groups, conn)
  end)
end

local function get_account(app, v, raw_pwd, conn)
  local types = tcheck({'*', 'string|number', 'string|nil', 'table|nil'}, app, v, raw_pwd, conn)

  local close = not conn
  if not conn then
    local err; conn, err = app:db()
    if not conn then
      return nil, err
    end
  end
  return conn:with(close, function()
    if types[2] == 'string' then
      return Account.by_email(v, raw_pwd, conn)
    else
      return Account.by_id(v, raw_pwd, conn)
    end
  end)
end

local M = {
  requires = {
    'tulip.pkg.database',
    'tulip.pkg.middleware',
    'tulip.pkg.mqueue',
    'tulip.pkg.token',
  },
}

local MWPREFIX = 'tulip.pkg.account'

-- table of middleware name to default handler.
local MWCONFIG = {
  signup = handler.errhandler{EINVAL = 400; function(_, res, _, err)
    if xerror.is_sql_state(err, "23505") then
      res:write{status = 409, body = handler.HTTPSTATUS[409]}
    else
      xerror.throw(err)
    end
  end},
  login = handler.errhandler{EINVAL = 401},
  check_session = handler.errhandler{},
  logout = handler.errhandler{},
  delete = handler.errhandler{EINVAL = 400},
  init_vemail = handler.errhandler{EINVAL = 400},
  vemail = handler.errhandler{EINVAL = 400},
  setpwd = handler.errhandler{EINVAL = 400},
  init_resetpwd = handler.errhandler{EINVAL = 200},
  resetpwd = handler.errhandler{EINVAL = 400},
  init_changeemail = handler.errhandler{EINVAL = 400},
  changeemail = handler.errhandler{EINVAL = 400},
  authz = handler.errhandler{function(req, res)
    if not req.locals.account then
      res:write{status = 401, body = handler.HTTPSTATUS[401]}
    else
      res:write{status = 403, body = handler.HTTPSTATUS[403]}
    end
  end},
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
--
--  * auth_key: string = authentication key for all signed tokens.
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
--    * signup = by default, 400 if EINVAL, 409 if SQL with state 23505, or throws the error
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
--   > groups: array of strings|nil = the group(s) this account belongs to
--   > conn: connection|nil = optional database connection to use
--
--   < acct: Account = the created Account instance
--   < err: Error|nil = error message if acct is nil
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
--   < err: Error|nil = error message if acct is nil
--
-- ok, err = Account:delete(conn)
--
--   Deletes the account.
--
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: Error|nil = error message if ok is falsy
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
--   < err: Error|nil = error message if ok is falsy
--
-- ok, err = Account:change_pwd(new_pwd, conn)
--
--   Updates the account's password to new_pwd.
--
--   > new_pwd: string = the new raw password
--   > conn: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: Error|nil = error message if ok is falsy
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
--   < err: Error|nil = error message if ok is falsy
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
--   < err: Error|nil = error message if ok is falsy
--
-- Middleware:
--
-- * tulip.pkg.account:signup
--
--   Handles the signup workflow (e.g. on POST of a form). On success,
--   the created account is stored in req.locals.account.
--
--   > email: string = form field with the email address
--   > password: string = form field with the raw password
--   > password2: string|nil = optional form field with the raw password again
--
-- * tulip.pkg.account:login
--
--   Handles the login workflow (e.g. on POST of a form). On success,
--   the logged-in account is stored under req.locals.account and
--   a session is initiated, with its id stored under req.locals.session_id
--   and a session cookie stored in the response's headers.
--
--   > email: string = form field with the email address
--   > password: string = form field with the raw password
--   > rememberme: string = if not an empty string, indicates that the session should be persisted
--
-- * tulip.pkg.account:check_session
--
--   Decodes the request's session cookie if present and valid, and sets
--   the req.locals.session_id and req.locals.account fields. Note that
--   it does not deny access if invalid or absent, use the authz middleware
--   to that effect.
--
-- * tulip.pkg.account:logout
--
--   Handles the logout workflow, which deletes the session cookie and token
--   and unsets the req.locals.session_id and req.locals.account fields.
--
-- * tulip.pkg.account:delete
--
--   Handles the delete account workflow (e.g. on POST of a form). On success,
--   the account is deleted as well as all session tokens and any session
--   cookie, and req.locals.session_id and req.locals.account are unset.
--
--   > password: string = the raw password of the acount, must be validated
--     to proceed with account deletion.
--
-- * tulip.pkg.account:init_vemail
--
--   Initiates the verify email workflow, typically after a successful signup
--   middleware. It generates a single-use token and enqueues a job to send
--   an email message to the account. Can also be set as middleware to a
--   "resend verify email" endpoint. Requires req.locals.account to be set
--   (which the signup middleware does set on success).
--
-- * tulip.pkg.account:vemail
--
--   Handles the verify email workflow. Checks that the token is valid
--   and if so marks the email as verified.
--
--   > t: string = the token, stored in a query string parameter.
--   > e: string = the email to verify, stored in a query string parameter.
--
-- * tulip.pkg.account:setpwd
--
--   Handles the update password workflow (e.g. on POST of a form). Must be
--   logged-in (i.e. the Account must be stored in req.locals.account).
--
--   > old_password: string = the old (raw) password
--   > new_password: string = the new (raw) password
--   > new_password2: string|nil = optional confirmation of the new (raw) password
--
-- * tulip.pkg.account:init_resetpwd
--
--   Initiates the reset password workflow, typically from a request on the
--   login form when the user forgets their password. It generates a single-use
--   token and sends an email message to the account.
--
--   > email: string = the email to which the reset token should be sent.
--
-- * tulip.pkg.account:resetpwd
--
--   Handles the reset password workflow (e.g. on POST of form). Checks that the
--   token is valid and if so, updates the password to the new one.
--
--   > t: string = the token, either as query string or in a form field
--   > e: string = the email used to reset the password, either as query
--     string or in a form field
--   > new_password: string = the new (raw) password
--   > new_password2: string|nil = optional confirmation of the new (raw) password
--
-- * tulip.pkg.account:init_changeemail
--
--   Initiates the change email workflow. It generates a single-use
--   token and sends an email message to the specified new email
--   address. Requires req.locals.account to be set.
--
--   > new_email: string = the new email to which the reset token
--     should be sent.
--   > password: string = the raw password of the acount, must be validated
--     to proceed with changing the email.
--
-- * tulip.pkg.account:changeemail
--
--   Handles the change email workflow. Checks that the token is valid
--   and if so updates the corresponding account's email address to
--   the new one.
--
--   > t: string = the token, stored in a query string parameter.
--   > oe: string = the old email, as query string
--   > ne: string = the new email, as query string
--
-- * tulip.pkg.account:authz
--
--   Handles authorization based on the routeargs of the request. As such,
--   it must be set on the routes' middleware, not as global middleware
--   (because the routes package sets the routeargs). By default, renders
--   either 403 if user is authenticated but doesn't have required group
--   membership or 401 if user is not authenticated. Supports the following
--   pseudo-groups:
--
--   - '?': authorize/deny anyone, authenticated or not
--   - '*': authorize/deny any authenticated user
--   - '@': authorize/deny any verified authenticated user
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.create_account = create_account
  app.account = get_account
  app:register_migrations('tulip.pkg.account', migrations)

  -- register the middleware
  local mwcfg = xtable.merge({}, cfg)
  for k, v in pairs(MWDEFAULTS) do
    mwcfg[k] = xtable.merge({}, v, cfg[k])
  end

  for k, h in pairs(MWCONFIG) do
    local errh = cfg.error_handlers and cfg.error_handlers[k] or h
    app:register_middleware(MWPREFIX .. ':' .. k, fn.partialtrail(middleware[k], 3, errh, mwcfg))
  end
end

return M
