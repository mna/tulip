local fn = require 'fn'
local pubsub = require 'web.pkg.pubsub.pubsub'
local tcheck = require 'tcheck'

local function make_pubsub(cfg)
  local lookup_chans
  if cfg.allowed_channels then
    lookup_chans = {}
    for _, chan in ipairs(cfg.allowed_channels) do
      lookup_chans[chan] = true
    end
  end

  local state = {
    handlers = {},
    error_handler = cfg.error_handler or pubsub.default_err_handler,
  }

  return function(app, chan, fdb, msg, cq)
    tcheck({'*', 'string', 'function|table|nil', 'table|nil'}, app, chan, fdb, msg)
    if lookup_chans and not lookup_chans[chan] then
      return nil, string.format('channel %q is invalid', chan)
    end

    if not state.connect then
      state.connect = cfg.get_connection or fn.partial(app.db, app)
    end

    if msg then
      local close = not fdb
      local db = fdb or app:db()
      return db:with(close, function(c)
        return pubsub.publish(chan, c, msg)
      end)
    else
      return pubsub.subscribe(chan, fdb, state, cq)
    end
  end
end

local M = {}

-- The pubsub package registers an App:pubsub method that either
-- publishes a notification on a channel, or subscribes to
-- notifications on a channel.
--
-- Requires: a database package
-- Config:
--   * allowed_channels: array of string = if set, only those channels
--     will be allowed.
--   * get_connection: function = if set, used to get the long-running
--     connection used to listen for notifications (and re-connect if
--     connection is lost). Defaults to app:db().
--   * error_handler: function = if set, called whenever an error occurs
--     in the background coroutine that dispatches notifications. It is
--     called with the current xpgsql connection, a number that increments
--     with each failure (first call is 1), a (possibly nil) error message
--     and the get_connection function.
--     If the function returns nil, the coroutine is terminated and
--     pubsub notifications will stop being emitted. Otherwise, it can
--     return a connection and an optional integer, and if so the
--     connection will be used instead of the old connection, and the
--     number will be used as new value for the failure count (e.g.
--     return 0 to reset). By default, a function that calls
--     get_connection to get a new connection, and fails permanently
--     (i.e. returns nil) after 3 calls.
--   * listeners: table = if set, key is the channel and value is an
--     array of functions to register as listeners for that channel.
--
-- ok, err = App:pubsub(chan, fdb[, msg])
--   > chan: string = then pubsub channel
--   > fdb: function|connection|nil = either a function to register
--     as handler for that channel, or an optional database
--     connection to use to publish msg. The handler function receives
--     a Notification object as argument with a channel and payload
--     field. It also has a :terminate() method to terminate the
--     pubsub notification coroutine, mostly for tests.
--   > msg: table|nil = the payload of the notification to publish.
--   < ok: bool|nil = returns a boolean that indicates if the
--     notification was published or the handler registered, nil
--     on error.
--   < err: string|nil = error message if ok is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  -- TODO: make the pubsub func a table with __call that holds the state,
  -- so that activate can refer to it and set the cq in a less convoluted
  -- way.
  -- TODO: test pubsub usage in a representative way, e.g. for server-sent
  -- events or websocket, see if it is usable.
  app.pubsub = make_pubsub(cfg)

  if not app.config.database then
    error('no database registered')
  end
end

function M.activate(app, cq)
  tcheck('web.App', app)

  local cfg = app.config.pubsub
  cfg.listeners = cfg.listeners or {}
  for chan, fns in pairs(cfg.listeners) do
    for _, f in ipairs(fns) do
      assert(app:pubsub(chan, f, nil, cq))
    end
  end
end

return M
