local fn = require 'fn'
local pubsub = require 'tulip.pkg.pubsub.pubsub'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'
local xtable = require 'tulip.xtable'

local function make_pubsub(cfg)
  local lookup_chans
  if cfg.allowed_channels then
    lookup_chans = xtable.toset(cfg.allowed_channels)
  end

  local state = {
    handlers = {},
    error_handler = cfg.error_handler or pubsub.default_err_handler,
  }

  return function(app, chan, fconn, msg, cq)
    tcheck({'*', 'string', 'function|table|nil', 'table|nil'}, app, chan, fconn, msg)

    if lookup_chans then
      local ok, err = xerror.inval(lookup_chans[chan],
        'channel is invalid', 'channel', chan)
      if not ok then
        return nil, err
      end
    end

    if not state.connect then
      state.connect = cfg.get_connection or fn.partial(app.db, app)
    end

    if msg then
      local close = not fconn
      if not fconn then
        local err; fconn, err = app:db()
        if not fconn then
          return nil, err
        end
      end
      return fconn:with(close, function(c)
        return pubsub.publish(chan, c, msg)
      end)
    else
      return pubsub.subscribe(chan, fconn, state, cq)
    end
  end
end

local M = {
  requires = {
    'tulip.pkg.database',
  },
}

-- The pubsub package registers an App:pubsub method that either
-- publishes a notification on a channel, or subscribes to
-- notifications on a channel.
--
-- Requires: database package
--
-- Config:
--
--   * allowed_channels: array of string = if set, only those channels
--     will be allowed.
--   * get_connection: function = if set, used to get the long-running
--     connection used to listen for notifications (and re-connect if
--     connection is lost). Defaults to App:db().
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
-- Methods:
--
-- ok, err = App:pubsub(chan, fconn[, msg])
--
--   Publishes a notification on a channel if msg is provided, or subscribes to
--   notifications on a channel.
--
--   > chan: string = the pubsub channel
--   > fconn: function|connection|nil = either a function to register
--     as handler for that channel, or an optional database
--     connection to use to publish msg. The handler function receives
--     a Notification object as argument with a channel and payload
--     field. It also has a terminate method to terminate the
--     pubsub notification coroutine, mostly for tests.
--   > msg: table|nil = the payload of the notification to publish.
--   < ok: boolean = true on success
--   < err: Error|nil = error message if ok is falsy
--
-- true = Notification:terminate()
--
--   Terminates the subscription to the channel that generated this
--   Notification.
--
--   < true = always returns true
--
-- Notification.channel: string
--
--   The name of the channel that received this Notification.
--
-- Notification.payload: table
--
--   The JSON-decoded payload that was sent with the Notification.
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  -- TODO: make the pubsub func a table with __call that holds the state,
  -- so that activate can refer to it and set the cq in a less convoluted
  -- way.
  -- TODO: test pubsub usage in a representative way, e.g. for server-sent
  -- events or websocket, see if it is usable.
  app.pubsub = make_pubsub(cfg)
end

function M.activate(cfg, app, cq)
  tcheck({'table', 'tulip.App'}, cfg, app)

  if cfg.listeners then
    for chan, fns in pairs(cfg.listeners) do
      for _, f in ipairs(fns) do
        xerror.must(app:pubsub(chan, f, nil, cq))
      end
    end
  end
end

return M
