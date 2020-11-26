local cjson = require('cjson.safe').new()
local xerror = require 'web.xerror'

local SQL_SCHEDULECMD = [[
  SELECT
    cron.schedule($1, $2, $3)
]]

local SQL_SCHEDULEJOB = [[
  SELECT
    cron.schedule($1, $2,
      'SELECT web_pkg_mqueue_enqueue('%s', %d::smallint, %d::integer, '%s')')
]]

local SQL_UNSCHEDULE = [[
  SELECT
    cron.unschedule($1)
]]

local M = {}

function M.schedule(job, conn, t)
  if t.command then
    xerror.must(xerror.db(conn:query(SQL_SCHEDULECMD, job, t.schedule, t.command)))
  else
    local payload = t.payload or {}
    if type(payload) == 'function' then
      payload = xerror.must(payload(job, conn, t))
    end

    local json = cjson.encode(payload)
    -- format the schedule job SQL statement with properly-escaped
    -- text values for the queue name and the payload.
    local qname = conn:format_array{job}
    local jsonstr = conn:format_array{json}
    local stmt = string.format(SQL_SCHEDULEJOB, qname, t.max_attempts, t.max_age, jsonstr)
    xerror.must(xerror.db(conn:query(stmt, job, t.schedule)))
  end
  return true
end

function M.unschedule(job, conn)
  xerror.must(xerror.db(conn:query(SQL_UNSCHEDULE, job)))
  return true
end

return M
