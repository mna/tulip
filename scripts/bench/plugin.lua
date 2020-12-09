local tcheck = require 'tcheck'
local xio = require 'tulip.xio'
local xpgsql = require 'xpgsql'

local MIGRATIONS = {
  -- create the test table
  function (conn)
    assert(conn:exec[[
      CREATE TABLE "scripts_bench_plugin" (
        "id"      SERIAL NOT NULL,
        "name"    VARCHAR(20) NOT NULL,
        "created" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

        PRIMARY KEY ("id")
      )
    ]])
    assert(conn:exec[[
      CREATE INDEX ON "scripts_bench_plugin" ("name")
    ]])
  end,

  -- generate random data
  function (conn)
    for _ = 1, 1000 do
      local nm = xio.b64encode(xio.random(10))
      assert(conn:exec([[
        INSERT INTO
          "scripts_bench_plugin" ("name")
        VALUES
          ($1)
      ]], nm))
    end
  end,
}

local function model(o)
  o.id = tonumber(o.id)
  return o
end

local function mw(req, res, nxt)
  local app = req.app
  local start = req.pathargs[1]
  if (not start) or start == '' then
    start = xio.b64encode(xio.random(2))
  end

  local rows = app:db(function (conn)
    return xpgsql.models(assert(conn:query([[
      SELECT
        "id", "name"
      FROM
        "scripts_bench_plugin"
      WHERE
        "name" > $1
      ORDER BY
        "name"
      LIMIT $2
    ]], start, 10)), model)
  end)

  res:write{
    status = 200,
    content_type = 'application/json',
    body = rows,
  }
  nxt()
end

local M = {}

function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  local db = app.config.database
  if not db then
    error('no database registered')
  end
  db.migrations = db.migrations or {}
  table.insert(db.migrations, {
    package = 'scripts.bench.plugin';
    table.unpack(MIGRATIONS)
  })

  app:register_middleware('scripts.bench.plugin', mw)
end

return M
