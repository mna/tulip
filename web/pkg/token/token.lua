local xerror = require 'web.xerror'
local xio = require 'web.xio'
local xpgsql = require 'xpgsql'

local TOKEN_LEN = 32

local MIGRATIONS = {
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE TABLE "web_pkg_token_tokens" (
        "token"   CHAR(44) NOT NULL,
        "type"    VARCHAR(20) NOT NULL,
        "once"    BOOLEAN NOT NULL,
        "ref_id"  INTEGER NOT NULL,
        "expiry"  INTEGER NOT NULL CHECK ("expiry" > 0),
        "created" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("token"),
        UNIQUE ("type", "ref_id")
      )
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "web_pkg_token_tokens" ("expiry");
    ]]))
  end,
  [[
    CREATE PROCEDURE "web_pkg_token_expire" ()
    LANGUAGE SQL
    AS $$
      DELETE FROM
        "web_pkg_token_tokens"
      WHERE
        "expiry" < EXTRACT(epoch FROM now())
    $$;
  ]],
  -- schedule expiration of tokens every day at 1AM
  function (conn)
    xerror.must(xerror.db(conn:query[[
      SELECT
        cron.schedule('web_pkg_token:expire', '0 1 * * *', 'CALL web_pkg_token_expire()')
    ]]))
  end,
}

local SQL_CREATETOKEN = [[
INSERT INTO
  "web_pkg_token_tokens" (
    "token",
    "type",
    "once",
    "ref_id",
    "expiry"
  )
VALUES
  ($1, $2, $3, $4, $5)
ON CONFLICT ("type", "ref_id") DO UPDATE SET
  "token" = $1,
  "once" = $3,
  "expiry" = $5
]]

local SQL_LOADTOKEN = [[
SELECT
  "token",
  "type",
  "once",
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
  o.once = o.once == 't'
  return o
end

local M = {
  migrations = MIGRATIONS,
}

function M.validate(t, conn, tok)
  local res, err = xerror.db(conn:query(SQL_LOADTOKEN, tok))
  if not res then return nil, xerror.ctx(err, 'validate') end

  local row = xpgsql.model(res, model)
  if not row then return false end -- invalid token

  -- at this point, if the token has once set, the token exists
  -- and is consumed (or leaked), so delete it.
  if row.once then
    res, err = xerror.db(conn:exec(SQL_DELETETOKEN, tok))
    if not res then return nil, xerror.ctx(err, 'validate') end
  end

  if t.type == row.type and ((not row.once) or (t.ref_id == row.ref_id)) and os.time() < row.expiry then
    return true, row.ref_id
  end
  return false
end

function M.generate(t, conn)
  local tok = xio.b64encode(xio.random(TOKEN_LEN))
  local ok, err = xerror.db(conn:exec(SQL_CREATETOKEN,
    tok, t.type, (t.once or false), t.ref_id, os.time() + t.max_age))
  if not ok then return nil, xerror.ctx(err, 'generate') end
  return tok
end

return M
