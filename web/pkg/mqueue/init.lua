local mqueue = require 'web.pkg.mqueue.mqueue'
local tcheck = require 'tcheck'
local xtable = require 'web.xtable'

local function make_mqueue(cfg)
  local def_max_age = cfg.default_max_age
  local def_max_att = cfg.default_max_attempts
  local lookup_queues
  if cfg.allowed_queues then
    lookup_queues = {}
    for _, q in ipairs(cfg.allowed_queues) do
      lookup_queues[q] = true
    end
  end

  return function(app, t, db, msg)
    tcheck({'*', 'table', 'table|nil', 'table|nil'}, app, t, db, msg)
    if lookup_queues and not lookup_queues[t.queue] then
      return nil, string.format('queue %q is invalid', t.queue)
    end

    local close = not db
    db = db or app:db()
    return db:with(close, function()
      if msg then
        -- enqueue the message
        return mqueue.enqueue(
          xtable.merge({
            max_age = def_max_age,
            max_attempts = def_max_att,
          }, t),
          db, msg)
      else
        -- dequeue some messages
        return mqueue.dequeue(xtable.merge({max_receive = 1}, t), db)
      end
    end)
  end
end

local M = {}

-- The mqueue package registers an App:mqueue method that either
-- enqueues a message, or dequeues a batch of messages to process.
--
-- Requires: a database package
-- Config:
--   * allowed_queues: array of string = if set, only those queues
--     will be allowed.
--   * default_max_age: integer|nil = if set, use as default max age
--     for the messages.
--   * default_max_attempts: integer|nil = if set, use as default
--     maximum number of attempts to process a message.
--
-- v, err = App:mqueue(t[, db[, msg]])
--   > t: table = a table with the following fields:
--     * t.max_attempts: number|nil = maximum number of attempts (enqueue only)
--     * t.max_age: number|nil = number of seconds to process message (enqueue only)
--     * t.queue: string = queue name
--     * t.max_receive: number|nil = maximum number of messages to
--       receive, when the call is a dequeue operation. Defaults to 1.
--   > db: connection|nil = optional database connection to use
--   > msg: table|nil = if provided, enqueues that message. It
--       gets encoded as JSON.
--   < v: bool|array of tables|nil = if msg is provided, returns a boolean
--     that indicates if the message was enqueued, otherwise returns an
--     array of tables representing the messages to process. Each table has
--     an id and a payload fields and a :done(conn) method. Is nil on error.
--   < err: string|nil = error message if v is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.mqueue = make_mqueue(cfg)

  local db = app.config.database
  if not db then
    error('no database registered')
  end
  db.migrations = db.migrations or {}
  table.insert(db.migrations, {
    package = 'web.pkg.mqueue';
    table.unpack(mqueue.migrations)
  })
end

return M
