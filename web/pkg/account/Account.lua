local argon2 = require 'argon2'
local xio = require 'web.xio'
local xpgsql = require 'xpgsql'
local xstring = require 'web.xstring'

local SQL_CREATEUSER = [[
INSERT INTO
  "web_pkg_account_accounts" (
    "email",
    "password"
  )
VALUES
  ($1, $2)
RETURNING
  "id"
]]

local SQL_LOADUSER = [[
SELECT
  "id",
  "email",
  "password",
  "verified"
FROM
  "web_pkg_account_accounts"
WHERE
  "email" = $1
]]

local SQL_DELETEUSER = [[
DELETE FROM
  "web_pkg_account_accounts"
WHERE
  "email" = $1
]]

local SQL_DELETEEMAILMEMBERS = [[
DELETE
  FROM
    "web_pkg_account_members" AS m
  USING
    "web_pkg_account_accounts" AS a
WHERE
  m.account_id = a.id AND
  a.email = $1
]]

local ARGON2_PARAMS = {
  t_cost = 3,
  m_cost = 2^16, -- 64KB
  parallelism = 1,
  hash_len = 32,
  salt_len = 16,
  variant = argon2.variants.argon2_id,
}

local function model(o)
  o.id = tonumber(o.id)
  o.verified = o.verified ~= nil
  return o
end

local Account = {__name = 'web.pkg.account.Account'}
Account.__index = Account

-- Create an account with email and raw_pwd. The email is trimmed
-- for spaces and lowercased, and the password is hashed with argon2.
-- Returns the new account id on success, or nil and an error message.
function Account:create(email, raw_pwd, db)
  local salt = xio.random(ARGON2_PARAMS.salt_len)
  local enc_pwd, err = argon2.hash_encoded(raw_pwd, salt, ARGON2_PARAMS)
  if not enc_pwd then
    return nil, err
  end
  email = string.lower(xstring.trim(email))

  local close = not db
  db = db or self.app:db()
  return db:with(close, function()
    local res = assert(db:query(SQL_CREATEUSER, email, enc_pwd))
    return tonumber(res[1][1])
  end)
end

-- Validates credentials for the specified email and raw_pwd. Returns the
-- authenticated account on success or nil and an error message.
function Account:validate(email, raw_pwd, db)
  local acct = self:lookup_email(email, db)
  if not acct then
    return nil, 'no such account'
  end
  local ok, err = argon2.verify(acct.password, raw_pwd)
  if not ok then
    return nil, err
  end
  return acct
end

-- Starts a web session by storing a session token in a cookie.
function Account:start_session(acct, res)
  -- TODO: only acts on the session, creates the cookie
end

-- Ends a web session by removing the session token cookie.
function Account:end_session(res)
  -- TODO: only acts on the session, removes the cookie
end

-- Returns the account instance corresponding to this email.
-- On error, returns nil and an error message.
function Account:lookup_email(email, db)
  email = string.lower(xstring.trim(email))

  local close = not db
  db = db or self.app:db()
  return db:with(close, function()
    return xpgsql.model(assert(db:query(SQL_LOADUSER, email)), model)
  end)
end

-- Deletes the account corresponding to this email.
-- Returns true on success, or nil and an error message.
function Account:delete(email, db)
  email = string.lower(xstring.trim(email))

  local close = not db
  db = db or self.app:db()
  return db:with(close, function()
    return db:ensuretx(function()
      assert(db:exec(SQL_DELETEEMAILMEMBERS, email))
      assert(db:exec(SQL_DELETEUSER, email))
      return true
    end)
  end)
end

function Account:verify_email()

end

function Account:change_pwd()

end

function Account:reset_pwd()

end

function Account:change_email()

end

function Account:membership()

end

function Account.new(app)
  return setmetatable({app = app}, Account)
end

return Account
