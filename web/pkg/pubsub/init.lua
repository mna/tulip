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
  }

  return function(app, chan, fdb, msg)
    tcheck({'*', 'string', 'function|table|nil', 'table|nil'}, app, chan, fdb, msg)
    if lookup_chans and not lookup_chans[chan] then
      error(string.format('channel %q is invalid', chan))
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
      return pubsub.subscribe(chan, fdb, state)
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
--
-- ok, err = App:pubsub(chan, fdb[, msg])
--   > chan: string = then pubsub channel
--   > fdb: function|connection|nil = either a function to register
--     as handler for that channel, or an optional database
--     connection to use to publish msg.
--   > msg: table|nil = the payload of the notification to publish.
--   < ok: bool|nil = returns a boolean that indicates if the
--     notification was published or the handler registered, nil
--     on error.
--   < err: string|nil = error message if ok is nil.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.pubsub = make_pubsub(cfg)

  if not app.config.database then
    error('no database registered')
  end
end

return M
