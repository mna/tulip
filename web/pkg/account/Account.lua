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

-- Attempts a login for the specified email and raw_pwd. Returns the
-- authenticated account on success or nil and an error message.
-- TODO: what/where is the session id set on req, and cookie sent?
function Account:login(email, raw_pwd, db)
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

function Account:logout()
  -- TODO: only acts on the session, removes the cookie and locals
end

function Account:lookup_email(email, db)
  email = string.lower(xstring.trim(email))

  local close = not db
  db = db or self.app:db()
  return db:with(close, function()
    return xpgsql.model(assert(db:query(SQL_LOADUSER, email)), model)
  end)
end

function Account:delete()

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
