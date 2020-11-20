local tcheck = require 'tcheck'
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

-- The account package handles account creation and management, so
-- that new accounts can be created, login and logout supported,
-- sessions created via a cookie, etc. It also supports the email
-- verification, password reset and email change workflows.
--
-- It registers two methods on the App instance and a number of methods are
-- also available on the Account instance returned by App:create_account or
-- App:account. It also registers a number of middleware, described below.
--
-- Requires: database and token packages.
-- Config:
--  * ...
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
--   Handles the signup workflow (POST of a form). On success, redirects
--   to the login URL (or should that be a subsequent "redirect" middleware?).
--
--   > email: string = form field with the email address
--   > password: string = form field with the raw password
--   > password2: string|nil = optional form field with the raw password again
--
-- * web.pkg.account:login
--
--   Handles the login workflow (POST of a form). On success, redirects
--   to the target URL (or should that be a subsequent "redirect" middleware?).
--
--   > email: string = form field with the email address
--   > password: string = form field with the raw password
--   > rememberme: boolean = indicates if the session should be persisted
--
-- * web.pkg.account:logout
--
--   Handles the logout workflow. On success, redirects to the target
--   URL (or should that be a subsequent "redirect" middleware?).
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
--   Initiates the verify email workflow, typically after a successful
--   signup middleware. It generates a single-use token and sends an email
--   message to the account. Can also be set as middleware to a "resend
--   verify email" endpoint.
--
--   > email: string = the email to which the token should be sent.
--
-- * web.pkg.account:vemail
--
--   Handles the verify email workflow. Checks that the token is valid
--   and if so marks the email as verified.
--
--   > t: string = the token, stored in a query string parameter.
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
--   > t: string = the token, usually stored in a hidden field in the GET
--     of the form or set there via javascript (from the query string).
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
--
-- * web.pkg.account:authz
--
--   Handles authorization based on the routeargs of the request, renders
--   either 403 if user is authenticated but doesn't have required group
--   membership, 401 if user is not authenticated, or 302 Found and redirect to
--   login page.
--
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.create_account = create_account
  app.account = get_account

  if not app.config.database then
    error('no database registered')
  end
  if not app.config.token then
    error('no token registered')
  end
end

return M
