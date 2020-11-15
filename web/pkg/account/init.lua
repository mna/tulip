local tcheck = require 'tcheck'
local Account = require 'web.pkg.account.Account'

local M = {}

-- The account package handles account creation and management, so
-- that new accounts can be created, login and logout supported,
-- sessions created via a cookie, etc. It also supports the email
-- verification, password reset and email change workflows.
--
-- It registers two methods on the App instance and a number of
-- methods are also available on the Account instance
-- returned by App:create_account or App:account.
--
-- TODO: It also registers a number of middleware.
--
-- Requires: database and token packages.
-- Config:
--  * ...
--
-- Methods:
--
-- acct, err = App:create_account(email, raw_pwd[, db])
--
--   Creates a new Account.
--
--   > email: string = the email address
--   > raw_pwd: string = the raw (unhashed) password
--   > db: connection|nil = optional database connection to use
--
--   < acct: Account = the created Account instance
--   < err: string|nil = error message if acct is nil
--
-- acct, err = App:account(v[, db[, raw_pwd]])
--
--   Lookups an existing Account.
--
--   > v: string|number = either the email address or account id
--   > db: connection|nil = optional database connection to use
--   > raw_pwd: string|nil = if provided, validates that it corresponds
--     to the password of this account.
--
--   < acct: Account = the corresponding Account instance, nil if
--     raw_pwd is provided but doesn't match the account's password.
--   < err: string|nil = error message if acct is nil
--
-- ok, err = Account:delete(db)
--
--   Deletes the account.
--
--   > db: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:verify_email(db)
--
--   Marks the account's email as verified. Note that this doesn't
--   generate nor validates a random token, nor does it send an
--   email for verification, it only sets the verified timestamp.
--
--   > db: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:change_pwd(new_pwd, db)
--
--   Updates the account's password to new_pwd.
--
--   > new_pwd: string = the new raw password
--   > db: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
-- ok, err = Account:change_email(new_email, db)
--
--   Updates the account's email address to new_email, and marks
--   it immediately as verified - as it should only be called once
--   that email address has been verified.
--
--   > new_email: string = the new email address
--   > db: connection = database connection to use
--
--   < ok: boolean = true on success
--   < err: string|nil = error message if ok is falsy
--
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.account = Account.new(app)

  if not app.config.database then
    error('no database registered')
  end
  if not app.config.token then
    error('no token registered')
  end

  -- TODO: Account methods
  -- TODO: middleware:
  -- * signup POST handler
  -- * login POST handler
  -- * authorization middleware, renders either 403 if user is authenticated
  --   but doesn't have required group membership, 401 if user is not
  --   authenticated, or 302 Found and redirect to login page.
  -- * logout handler
  -- * delete POST handler
  -- * change password POST handler
  -- * verify email, change email, reset pwd handlers (likely 3 per type:
  --   trigger the request - e.g. generate token and send email -, GET
  --   the confirmation form, and handle the POST form)
end

return M
