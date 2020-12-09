local cron = require 'tulip.pkg.cron.cron'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local xtable = require 'tulip.xtable'

local function make_schedule(cfg)
  local def_max_age = cfg.default_max_age or (24 * 3600)
  local def_max_att = cfg.default_max_attempts or 1
  local lookup_jobs
  if cfg.allowed_jobs then
    lookup_jobs = xtable.toset(cfg.allowed_jobs)
  end

  return function(app, job, conn, t)
    tcheck({'*', 'string', 'table|nil', 'string|table|nil'}, app, job, conn, t)

    if lookup_jobs then
      local ok, err = xerror.inval(lookup_jobs[job],
        'job is invalid', 'job', job)
      if not ok then
        return nil, err
      end
    end

    local close = not conn
    conn = conn or app:db()
    return conn:with(close, function()
      if t then
        if type(t) == 'string' then
          t = {schedule = t}
        end
        return cron.schedule(job, conn, xtable.merge({
          max_age = def_max_age,
          max_attempts = def_max_att,
        }, t))
      else
        return cron.unschedule(job, conn)
      end
    end)
  end
end

local M = {
  requires = {
    'tulip.pkg.database',
    'tulip.pkg.mqueue',
  },
}

-- The cron package registers an App:schedule method that registers
-- a job to run at a specific schedule.
--
-- Requires: a database package, an mqueue package.
-- Config:
--   * allowed_jobs: array of string = if set, only those jobs
--     will be allowed.
--   * default_max_age: integer|nil = if set, use as default max age
--     for the jobs messages, defaults to 24 hours.
--   * default_max_attempts: integer|nil = if set, use as default
--     maximum number of attempts to process a job's message, defaults
--     to 1.
--   * jobs: dictionary|nil = if set, list of jobs to schedule
--     at startup. The key is the job name, and the value is the same
--     as the t table that can be passed in App:schedule.
--
-- v, err = App:schedule(job[, conn[, t]])
--   > job: string = name of the job
--   > conn: connection|nil = optional database connection to use
--   > t: string|table|nil = if nil, unschedule the job.
--     If it is a string, it is the cron schedule, if it is a table,
--     it is a table with the following fields:
--     * t.schedule: string = the cron schedule
--     * t.max_attempts: number|nil = maximum number of attempts
--     * t.max_age: number|nil = number of seconds to process message
--     * t.command: string|nil = if set, the scheduled job will run this SQL command
--       instead of enqueueing a message.
--     * t.payload: table|function|nil = if set, will be the message's payload. If it is
--       a function, it is called with the job name, connection and config table and
--       its first return value is used as payload.
--   < v: bool|nil = true if the job was scheduled or unscheduled sucessfully,
--     nil on error.
--   < err: string|nil = error message if v is nil.
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.schedule = make_schedule(cfg)
end

function M.activate(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  if cfg.jobs then
    for job, t in pairs(cfg.jobs) do
      xerror.must(app:schedule(job, nil, t))
    end
  end
end

return M
