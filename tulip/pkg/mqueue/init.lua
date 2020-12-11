local mqueue = require 'tulip.pkg.mqueue.mqueue'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local xtable = require 'tulip.xtable'

local function make_mqueue(cfg)
  local def_max_age = cfg.default_max_age
  local def_max_att = cfg.default_max_attempts
  local lookup_queues
  if cfg.allowed_queues then
    lookup_queues = xtable.toset(cfg.allowed_queues)
  end

  return function(app, t, conn, msg)
    tcheck({'*', 'table', 'table|nil', 'table|nil'}, app, t, conn, msg)

    if lookup_queues then
      local ok, err = xerror.inval(lookup_queues[t.queue],
        'queue is invalid', 'queue', t.queue)
      if not ok then
        return nil, err
      end
    end

    local close = not conn
    conn = conn or app:db()
    return conn:with(close, function()
      if msg then
        -- enqueue the message
        return mqueue.enqueue(
          xtable.merge({
            max_age = def_max_age,
            max_attempts = def_max_att,
          }, t),
          conn, msg)
      else
        -- dequeue some messages
        return mqueue.dequeue(xtable.merge({max_receive = 1}, t), conn)
      end
    end)
  end
end

local M = {
  requires = {
    'tulip.pkg.database',
  },
}

-- The mqueue package registers an App:mqueue method that either
-- enqueues a message, or dequeues a batch of messages to process.
-- It implements a message queue with at-least-once delivery.
--
-- Requires: database package
--
-- Config:
--
--   * allowed_queues: array of string = if set, only those queues
--     will be allowed.
--   * default_max_age: integer|nil = if set, use as default max age
--     for the messages.
--   * default_max_attempts: integer|nil = if set, use as default
--     maximum number of attempts to process a message.
--
-- Methods:
--
-- v, err = App:mqueue(t[, conn[, msg]])
--
--   Enqueues a message, or dequeues a batch of messages to process.
--
--   > t: table = a table with the following fields:
--     * t.max_attempts: number|nil = maximum number of attempts (enqueue only)
--     * t.max_age: number|nil = number of seconds to process message (enqueue only)
--     * t.queue: string = queue name
--     * t.max_receive: number|nil = maximum number of messages to
--       receive, when the call is a dequeue operation. Defaults to 1.
--   > conn: connection|nil = optional database connection to use
--   > msg: table|nil = if provided, enqueues that message. It
--       gets encoded as JSON.
--   < v: bool|array of tables|nil = if msg is provided, returns a boolean
--     that indicates if the message was enqueued, otherwise returns an
--     array of tables representing the messages to process. Each table has
--     an id and a payload fields and a :done(conn) method. Is nil on error.
--   < err: Error|nil = error message if v is nil
--
-- res, err = Message:done(conn)
--
--   Marks the message as done so it isn't processed anymore. Note that if
--   the max age of the message was expired, the message would still be
--   pending again after the call.
--
--   > conn: connection = the database connection to use
--   < res: userdata = the database result
--   < err: Error|nil = error message if res is nil
--
-- Message.raw_payload: string
--
--   The JSON payload as a string, as stored in the DB.
--
-- Message.payload_err: string
--
--   The JSON decoding error, if any.
--
-- Message.payload: table
--
--   The payload as a Lua table, JSON-decoded.
--
-- Message.id: number
--
--   The id of the message.
--
-- Message.attempts: number
--
--   The number of attempts done so far (not including the current one).
--
-- Message.max_attempts: number
--
--   The maximum number of attempts for this message.
--
-- Message.max_age: number
--
--   The max age of this message (time allocated for processing).
--
-- Message.first_created: epoch
--
--   The timestamp when the message was first created, as epoch value.
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.mqueue = make_mqueue(cfg)
  app:register_migrations('tulip.pkg.mqueue', mqueue.migrations)
end

return M
