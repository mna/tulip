local SQL_SCHEDULECMD = [[
  SELECT
    cron.schedule($1, $2, $3)
]]

local SQL_SCHEDULEJOB = [[
  SELECT
    cron.schedule($1, $2, 'SELECT web_pkg_mqueue_enqueue(...)')
]]

local SQL_UNSCHEDULE = [[
  SELECT
    cron.unschedule($1)
]]

local M = {}

function M.schedule(job, db, t)
  if t.command then
    assert(db:query(SQL_SCHEDULECMD, job, t.schedule, t.command))
  else
    local payload = t.payload
    if type(payload) == 'function' then
      payload = assert(payload(job, db, t))
    end

    -- TODO: add a enqueue DB function in mqueue, and call this
    -- in the cron schedule
    assert(db:query(SQL_SCHEDULEJOB, job, t.schedule, t.max_age, t.max_attempts))
  end
end

function M.unschedule(job, db)
  assert(db:query(SQL_UNSCHEDULE, job))
  return true
end

return M
