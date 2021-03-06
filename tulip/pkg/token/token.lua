local xerror = require 'tulip.xerror'
local xio = require 'tulip.xio'
local xpgsql = require 'xpgsql'

local TOKEN_LEN = 32

local MIGRATIONS = {
  function (conn)
    xerror.must(xerror.db(conn:exec[[
      CREATE TABLE "tulip_pkg_token_tokens" (
        "token"   CHAR(44) NOT NULL,
        "type"    VARCHAR(100) NOT NULL,
        "once"    BOOLEAN NOT NULL,
        "ref_id"  INTEGER NOT NULL,
        "expiry"  BIGINT NOT NULL CHECK ("expiry" > 0),
        "created" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("token")
      )
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "tulip_pkg_token_tokens" ("expiry");
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE INDEX ON "tulip_pkg_token_tokens" ("ref_id");
    ]]))
    xerror.must(xerror.db(conn:exec[[
      CREATE UNIQUE INDEX ON "tulip_pkg_token_tokens" ("type", "ref_id")
        WHERE "once";
    ]]))
  end,
  [[
    CREATE PROCEDURE "tulip_pkg_token_expire" ()
    LANGUAGE SQL
    AS $$
      DELETE FROM
        "tulip_pkg_token_tokens"
      WHERE
        "expiry" < EXTRACT(epoch FROM now())
    $$;
  ]],
  -- schedule expiration of tokens every day at 1AM
  function (conn)
    xerror.must(xerror.db(conn:query[[
      SELECT
        cron.schedule('tulip_pkg_token:expire', '0 1 * * *', 'CALL tulip_pkg_token_expire()')
    ]]))
  end,
}

local SQL_CREATETOKEN = [[
INSERT INTO
  "tulip_pkg_token_tokens" (
    "token",
    "type",
    "once",
    "ref_id",
    "expiry"
  )
VALUES
  ($1, $2, $3, $4, $5)
ON CONFLICT ("type", "ref_id") WHERE "once" DO
UPDATE SET
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
  "tulip_pkg_token_tokens"
WHERE
  "token" = $1
]]

local SQL_DELETETOKEN = [[
DELETE FROM
  "tulip_pkg_token_tokens"
WHERE
  "token" = $1
]]

local SQL_DELETETOKENS = [[
DELETE FROM
  "tulip_pkg_token_tokens"
WHERE
  "ref_id" = $1 AND
  "type" = $2
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
  if t.delete and (not tok) then
    -- delete all tokens for that ref_id and type
    xerror.must(xerror.db(conn:exec(SQL_DELETETOKENS, t.ref_id, t.type)))
    return true
  end

  local res = xerror.must(xerror.db(conn:query(SQL_LOADTOKEN, tok)))
  local row = xerror.must(xerror.inval(xpgsql.model(res, model), 'invalid token'))

  -- at this point, if the token has once set, the token exists
  -- and is consumed (or leaked), so delete it.
  if row.once or t.delete then
    xerror.must(xerror.db(conn:exec(SQL_DELETETOKEN, tok)))
  end

  if t.type == row.type and ((not row.once) or (t.ref_id == row.ref_id))
      and os.time() < row.expiry then
    return true, row.ref_id
  end
  xerror.must(xerror.inval(nil, 'invalid token'))
end

function M.generate(t, conn)
  local tok = xio.b64encode(xio.random(TOKEN_LEN))
  xerror.must(xerror.db(conn:exec(SQL_CREATETOKEN,
    tok, t.type, (t.once or false), t.ref_id, os.time() + t.max_age)))
  return tok
end

return M
