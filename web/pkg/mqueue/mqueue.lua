local cjson = require('cjson.safe').new()
local fn = require 'fn'
local migrations = require 'web.pkg.mqueue.migrations'
local xpgsql = require 'xpgsql'
local xstring = require 'web.xstring'

local SQL_CREATEPENDING = [[
  SELECT
    web_pkg_mqueue_enqueue($1, $2::smallint, $3::integer, $4);
]]

local SQL_SELECTPENDING = [[
SELECT
  "id",
  "attempts",
  "max_attempts",
  "max_age",
  "queue",
  "payload",
  "first_created"
FROM
  "web_pkg_mqueue_pending"
WHERE
  "queue" = $1
ORDER BY
  "first_created"
LIMIT $2
FOR UPDATE SKIP LOCKED
]]

local SQL_COPYACTIVE = [[
INSERT INTO
  "web_pkg_mqueue_active"
  ("id", "attempts", "max_attempts", "max_age",
   "expiry", "queue", "payload", "first_created")
SELECT
  "id",
  "attempts" + 1,
  "max_attempts",
  "max_age",
  EXTRACT(epoch FROM now()) + "max_age",
  "queue",
  "payload",
  "first_created"
FROM
  "web_pkg_mqueue_pending"
WHERE
  "id" IN (%s)
]]

local SQL_DELETEPENDING = [[
DELETE FROM
  "web_pkg_mqueue_pending"
WHERE
  "id" IN (%s)
]]

local SQL_DELETEACTIVE = [[
DELETE FROM
  "web_pkg_mqueue_active"
WHERE
  id = $1
]]

local Message = {__name = 'web.pkg.mqueue.Message'}
Message.__index = Message

function Message:done(conn)
  return conn:exec(SQL_DELETEACTIVE, self.id)
end

local function model(o)
  o.id = tonumber(o.id)
  o.attempts = tonumber(o.attempts)
  o.max_attempts = tonumber(o.max_attempts)
  o.max_age = tonumber(o.max_age)
  o.payload = cjson.decode(o.payload)
  o.first_created = xstring.totime(o.first_created)
  setmetatable(o, Message)

  return o
end

local M = {
  migrations = migrations,
}

function M.enqueue(t, db, msg)
  local payload, e1 = cjson.encode(msg)
  if not payload then
    return nil, e1
  end

  local ok, e2 = db:query(SQL_CREATEPENDING,
    t.queue,
    t.max_attempts,
    t.max_age,
    payload)
  if not ok then
    return nil, e2
  end
  return true
end

function M.dequeue(t, db)
  return db:ensuretx(function(c)
    local rows = xpgsql.models(assert(
      c:query(SQL_SELECTPENDING, t.queue, t.max_receive)
    ), model)

    local ids = fn.reduce(function(cumul, _, row)
      table.insert(cumul, row.id)
      return cumul
    end, {}, ipairs(rows))
    if #ids > 0 then
      local stmt = string.format(SQL_COPYACTIVE, c:format_array(ids))
      assert(c:exec(stmt))
      stmt = string.format(SQL_DELETEPENDING, c:format_array(ids))
      assert(c:exec(stmt))
    end
    return rows
  end)
end

return M
