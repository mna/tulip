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

local SQL_ADDUSERMEMBER = [[
INSERT INTO
  "web_pkg_account_members" (
    "account_id",
    "group_id"
  )
VALUES
  ($1, (SELECT
          "id"
        FROM
          "web_pkg_account_groups"
        WHERE
          "name" = $2))
]]

local SQL_LOADUSEREMAIL = [[
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

local SQL_LOADUSERID = [[
SELECT
  "id",
  "email",
  "password",
  "verified"
FROM
  "web_pkg_account_accounts"
WHERE
  "id" = $1
]]

local SQL_LOADUSERMEMBERS = [[
SELECT
  g."name"
FROM
  "web_pkg_account_groups" g
INNER JOIN
  "web_pkg_account_members" m
ON
  g."id" = m."group_id"
WHERE
  m."account_id" = $1
]]

local SQL_DELETEUSER = [[
DELETE FROM
  "web_pkg_account_accounts"
WHERE
  "id" = $1
]]

local SQL_DELETEEMAILMEMBERS = [[
DELETE
  "web_pkg_account_members"
WHERE
  "account_id" = $1
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

local function create_account(email, raw_pwd, groups, conn)
  local salt = xio.random(ARGON2_PARAMS.salt_len)
  local enc_pwd = assert(
    argon2.hash_encoded(raw_pwd, salt, ARGON2_PARAMS))

  email = string.lower(xstring.trim(email))
  return conn:ensuretx(function()
    local res = assert(conn:query(SQL_CREATEUSER, email, enc_pwd))
    local id = tonumber(res[1][1])

    if groups then
      for _, g in ipairs(groups) do
        assert(conn:exec(SQL_ADDUSERMEMBER, id, g))
      end
    end
    return id
  end)
end

local function load_groups(acct, conn)
  local groups = xpgsql.model(assert(
    conn:query(SQL_LOADUSERMEMBERS, acct.id)))

  local ar = {}
  for _, g in ipairs(groups) do
    table.insert(ar, g.name)
  end
  acct.groups = ar
end

local Account = {__name = 'web.pkg.account.Account'}
Account.__index = Account

-- Deletes this account.
-- Returns true on success, or nil and an error message.
function Account:delete(conn)
  return conn:ensuretx(function()
    assert(conn:exec(SQL_DELETEEMAILMEMBERS, self.id))
    assert(conn:exec(SQL_DELETEUSER, self.id))
    return true
  end)
end

-- TODO: ideally a password change should reset any existing session
-- token, so that a login is required anew.
-- TODO: ideally an email change should reset any existing session
-- token, so that a login is required anew.

-- Returns the account instance corresponding to email. If raw_pwd
-- is provided, validates that passwords match and raise an error
-- otherwise.
function Account.by_email(email, raw_pwd, conn)
  email = string.lower(xstring.trim(email))
  local acct = xpgsql.model(assert(
    conn:query(SQL_LOADUSEREMAIL, email)), model)

  if raw_pwd then
    assert(argon2.verify(acct.password, raw_pwd))
  end
  load_groups(acct, conn)
  return acct
end

-- Returns the account instance corresponding to id. If raw_pwd
-- is provided, validates that passwords match and raise an error
-- otherwise.
function Account.by_id(id, raw_pwd, conn)
  local acct = xpgsql.model(assert(
    conn:query(SQL_LOADUSERID, id)), model)

  if raw_pwd then
    assert(argon2.verify(acct.password, raw_pwd))
  end
  load_groups(acct, conn)
  return acct
end

-- Create an account with email and raw_pwd. The email is trimmed
-- for spaces and lowercased, and the password is hashed with argon2.
-- Returns the new account on success, or nil and an error message.
function Account.new(email, raw_pwd, groups, conn)
  local id = create_account(email, raw_pwd, groups, conn)
  return Account.by_id(id, nil, conn)
end

return Account
