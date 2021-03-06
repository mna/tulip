local cjson = require('cjson.safe').new()
local fn = require 'fn'
local migrations = require 'tulip.pkg.mqueue.migrations'
local xerror = require 'tulip.xerror'
local xpgsql = require 'xpgsql'
local xstring = require 'tulip.xstring'

local SQL_CREATEPENDING = [[
  SELECT
    tulip_pkg_mqueue_enqueue($1, $2::smallint, $3::integer, $4);
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
  "tulip_pkg_mqueue_pending"
WHERE
  "queue" = $1
ORDER BY
  "first_created"
LIMIT $2
FOR UPDATE SKIP LOCKED
]]

local SQL_COPYACTIVE = [[
INSERT INTO
  "tulip_pkg_mqueue_active"
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
  "tulip_pkg_mqueue_pending"
WHERE
  "id" IN (%s)
]]

local SQL_DELETEPENDING = [[
DELETE FROM
  "tulip_pkg_mqueue_pending"
WHERE
  "id" IN (%s)
]]

local SQL_DELETEACTIVE = [[
DELETE FROM
  "tulip_pkg_mqueue_active"
WHERE
  id = $1
]]

local Message = {__name = 'tulip.pkg.mqueue.Message'}
Message.__index = Message

function Message:done(conn)
  return xerror.db(conn:exec(SQL_DELETEACTIVE, self.id))
end

local function model(o)
  o.raw_payload = o.payload
  local pld, err = cjson.decode(o.payload)
  o.payload = pld
  if not pld then
    o.payload_err = err
  end

  o.id = tonumber(o.id)
  o.attempts = tonumber(o.attempts)
  o.max_attempts = tonumber(o.max_attempts)
  o.max_age = tonumber(o.max_age)
  o.first_created = xstring.totime(o.first_created)
  return setmetatable(o, Message)
end

local M = {
  migrations = migrations,
}

function M.enqueue(t, conn, msg)
  local payload = xerror.must(cjson.encode(msg))

  xerror.must(xerror.db(conn:query(SQL_CREATEPENDING,
    t.queue,
    t.max_attempts,
    t.max_age,
    payload)))
  return true
end

function M.dequeue(t, conn)
  return conn:ensuretx(function(c)
    local rows = xpgsql.models(xerror.must(
      xerror.db(c:query(SQL_SELECTPENDING, t.queue, t.max_receive))
    ), model)

    local ids = fn.reduce(function(cumul, _, row)
      table.insert(cumul, row.id)
      return cumul
    end, {}, ipairs(rows))
    if #ids > 0 then
      local stmt = string.format(SQL_COPYACTIVE, c:format_array(ids))
      xerror.must(xerror.db((c:exec(stmt))))
      stmt = string.format(SQL_DELETEPENDING, c:format_array(ids))
      xerror.must(xerror.db((c:exec(stmt))))
    end
    return rows
  end)
end

return M
