local argon2 = require 'argon2'
local tcheck = require 'tcheck'
local xerror = require 'web.xerror'
local xio = require 'web.xio'
local xpgsql = require 'xpgsql'
local xstring = require 'web.xstring'
local xtable = require 'web.xtable'

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

local SQL_RMUSERMEMBER = [[
DELETE FROM
  "web_pkg_account_members" m
USING
  "web_pkg_account_groups" g
WHERE
  m."account_id" = $1 AND
  m."group_id" = g."id" AND
  g."name" = $2
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

local SQL_VERIFYEMAIL = [[
UPDATE
  "web_pkg_account_accounts"
SET
  "verified" = CURRENT_TIMESTAMP
WHERE
  "id" = $1 AND
  "verified" IS NULL
]]

local SQL_CHANGEPWD = [[
UPDATE
  "web_pkg_account_accounts"
SET
  "password" = $1
WHERE
  "id" = $2
]]

local SQL_CHANGEEMAIL = [[
UPDATE
  "web_pkg_account_accounts"
SET
  "email" = $1,
  "verified" = CURRENT_TIMESTAMP
WHERE
  "id" = $2
]]

local SQL_DELETEUSER = [[
DELETE FROM
  "web_pkg_account_accounts"
WHERE
  "id" = $1
]]

local SQL_DELETEEMAILMEMBERS = [[
DELETE FROM
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
  o.verified = (o.verified ~= nil) and (o.verified ~= '')
  return o
end

-- Returns the encrypted password or nil and an error message.
local function hash_pwd(raw_pwd)
  local salt = xio.random(ARGON2_PARAMS.salt_len)
  return argon2.hash_encoded(raw_pwd, salt, ARGON2_PARAMS)
end

local function create_account(email, raw_pwd, groups, conn)
  local enc_pwd = xerror.must(hash_pwd(raw_pwd))
  email = string.lower(xstring.trim(email))

  return xerror.must(conn:ensuretx(function()
    local res = xerror.must(xerror.db(conn:query(SQL_CREATEUSER, email, enc_pwd)))
    local id = tonumber(res[1][1])

    if groups then
      for _, g in ipairs(groups) do
        xerror.must(xerror.db(conn:exec(SQL_ADDUSERMEMBER, id, g)))
      end
    end
    return id
  end))
end

local function load_groups(acct, conn)
  local groups = xpgsql.models(xerror.must(xerror.db(
    conn:query(SQL_LOADUSERMEMBERS, acct.id))))

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
  tcheck({'*', 'table'}, self, conn)

  return conn:ensuretx(function()
    xerror.must(xerror.db(conn:exec(SQL_DELETEEMAILMEMBERS, self.id)))
    xerror.must(xerror.db(conn:exec(SQL_DELETEUSER, self.id)))
    return true
  end)
end

-- Marks the account's email as verified. Note that this doesn't
-- generate nor validates a random token, nor does it send an
-- email for verification, it only sets the verified timestamp.
-- Returns true on success, or nil and an error message.
function Account:verify_email(conn)
  tcheck({'*', 'table'}, self, conn)

  return conn:with(false, function()
    xerror.must(xerror.db(conn:exec(SQL_VERIFYEMAIL, self.id)))
    self.verified = true
    return true
  end)
end

-- Updates the account's password to new_pwd. Returns true on
-- success, or nil and an error message.
function Account:change_pwd(new_pwd, conn)
  tcheck({'*', 'string', 'table'}, self, new_pwd, conn)

  return conn:with(false, function()
    local enc_pwd = xerror.must(hash_pwd(new_pwd))
    xerror.must(xerror.db(conn:exec(SQL_CHANGEPWD, enc_pwd, self.id)))
    self.password = enc_pwd
    return true
  end)
end

-- Updates the account's email address to new_email, and marks
-- it immediately as verified - as it should only be called once
-- that email address has been verified.
-- Returns true on success, or nil and an error message.
function Account:change_email(new_email, conn)
  tcheck({'*', 'string', 'table'}, self, new_email, conn)

  return conn:with(false, function()
    new_email = string.lower(xstring.trim(new_email))
    xerror.must(xerror.db(conn:exec(SQL_CHANGEEMAIL, new_email, self.id)))
    self.email = new_email
    self.verified = true
    return true
  end)
end

-- Adds and/or removes the account from the groups. Group additions
-- are processed before group removal, so if the same group is in both
-- values, it will get removed.
-- Returns true on success, or nil and an error message.
function Account:change_groups(add, rm, conn)
  local types = tcheck({'*', 'string|table|nil', 'string|table|nil', 'table'}, self, add, rm, conn)

  return conn:ensuretx(function()
    if add then
      if types[2] == 'string' then
        add = {add}
      end
      for _, g in ipairs(add) do
        xerror.must(xerror.db(conn:exec(SQL_ADDUSERMEMBER, self.id, g)))
      end
    end

    if rm then
      if types[3] == 'string' then
        rm = {rm}
      end
      for _, g in ipairs(rm) do
        xerror.must(xerror.db(conn:exec(SQL_RMUSERMEMBER, self.id, g)))
      end
    end

    local set = xtable.toset(self.groups, add)
    self.groups = xtable.toarray(xtable.setdiff(set, xtable.toset(rm)))
    return true
  end)
end

-- Returns the account instance corresponding to email. If raw_pwd
-- is provided, validates that passwords match and raise an error
-- otherwise.
function Account.by_email(email, raw_pwd, conn)
  tcheck({'string', 'string|nil', 'table'}, email, raw_pwd, conn)

  email = string.lower(xstring.trim(email))
  local acct = xpgsql.model(xerror.must(xerror.db(
    conn:query(SQL_LOADUSEREMAIL, email))), model)
  if not acct then
    xerror.throw('account does not exist')
  end

  if raw_pwd then
    xerror.must(argon2.verify(acct.password, raw_pwd), 'invalid credentials')
  end
  load_groups(acct, conn)
  return setmetatable(acct, Account)
end

-- Returns the account instance corresponding to id. If raw_pwd
-- is provided, validates that passwords match and raise an error
-- otherwise.
function Account.by_id(id, raw_pwd, conn)
  tcheck({'number', 'string|nil', 'table'}, id, raw_pwd, conn)

  local acct = xpgsql.model(xerror.must(xerror.db(
    conn:query(SQL_LOADUSERID, id))), model)
  if not acct then
    xerror.throw('account does not exist')
  end

  if raw_pwd then
    xerror.must(argon2.verify(acct.password, raw_pwd), 'invalid credentials')
  end
  load_groups(acct, conn)
  return setmetatable(acct, Account)
end

-- Create an account with email and raw_pwd. The email is trimmed
-- for spaces and lowercased, and the password is hashed with argon2.
-- Returns the new account on success, or nil and an error message.
function Account.new(email, raw_pwd, groups, conn)
  tcheck({'string', 'string', 'table|nil', 'table'}, email, raw_pwd, groups, conn)

  local id = create_account(email, raw_pwd, groups, conn)
  return Account.by_id(id, nil, conn)
end

return Account
