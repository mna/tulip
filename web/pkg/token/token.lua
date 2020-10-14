local xio = require 'web.xio'
local xpgsql = require 'xpgsql'

local TOKEN_LEN = 32

local MIGRATIONS = {
  [[
    CREATE TABLE "web_pkg_token_tokens" (
      "token"   CHAR(44) NOT NULL,
      "type"    VARCHAR(20) NOT NULL,
      "ref_id"  INTEGER NOT NULL,
      "expiry"  INTEGER NOT NULL CHECK ("expiry" > 0),
      "created" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

      PRIMARY KEY ("token"),
      UNIQUE ("type", "ref_id")
    )
  ]],
}

local SQL_CREATETOKEN = [[
INSERT INTO
  "web_pkg_token_tokens" (
    "token",
    "type",
    "ref_id",
    "expiry"
  )
VALUES
  ($1, $2, $3, $4)
ON CONFLICT ("type", "ref_id") DO UPDATE SET
  "token" = $1,
  "expiry" = $4
]]

local SQL_LOADTOKEN = [[
SELECT
  "token",
  "type",
  "ref_id",
  "expiry"
FROM
  "web_pkg_token_tokens"
WHERE
  "token" = $1
]]

local SQL_DELETETOKEN = [[
DELETE FROM
  "web_pkg_token_tokens"
WHERE
  "token" = $1
]]

local function model(o)
  o.ref_id = tonumber(o.ref_id)
  o.expiry = tonumber(o.expiry)
  return o
end

local M = {
  migrations = MIGRATIONS,
}

function M.validate(t, db, tok)
  local res, err = db:query(SQL_LOADTOKEN, tok)
  if not res then return nil, err end

  local row = xpgsql.model(res, model)
  if not row then return false end -- invalid token

  -- at this point, the token exists and is consumed (or leaked), so
  -- delete it.
  res, err = db:exec(SQL_DELETETOKEN, tok)
  if not res then return nil, err end

  if t.type == row.type and t.refid == row.ref_id and os.time() < row.expiry then
    return true
  end
  return false
end

function M.generate(t, db)
  local tok = xio.b64encode(xio.random(TOKEN_LEN))
  local ok, err = db:exec(SQL_CREATETOKEN, tok, t.type, t.refid, os.time() + t.max_age)
  if not ok then return nil, err end
  return tok
end

return M
