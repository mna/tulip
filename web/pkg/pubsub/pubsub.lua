local cjson = require('cjson.safe').new()
local cqueues = require 'cqueues'
local xerror = require 'web.xerror'

local SQL_PUBLISH = [[
  SELECT
    pg_notify($1, $2)
]]

local SQL_SUBSCRIBE = [[
  LISTEN %q
]]

local Notification = {__name = 'web.pkg.pubsub.Notification'}
Notification.__index = Notification

function Notification:terminate()
  self._terminate = true
  return true
end

function Notification.new(n)
  local o = {
    channel = n:relname(),
    payload = cjson.decode(n:extra()),
  }
  return setmetatable(o, Notification)
end

local function on_error(state, errcount, err)
  local conn, n = state.error_handler(state.connection,
    errcount, err, state.connect)
  if conn then
    -- listen to all registered channels, cannot really do anything about
    -- LISTEN errors though...
    for chan in pairs(state.handlers) do
      conn:exec(string.format(SQL_SUBSCRIBE, chan))
    end
    state.connection = conn
    return conn._conn, n or errcount, false
  end
  return nil, errcount, true
end

local function make_notifier(state)
  local raw_conn = state.connection._conn
  local errcount = 0
  local stop = false

  return function()
    while not stop do
      local poll_obj = {pollfd = raw_conn:socket(), events = 'r'}
      do
        local o, err = cqueues.poll(poll_obj)
        if not o then
          cqueues.cancel(poll_obj)
          raw_conn, errcount, stop = on_error(state, errcount + 1, err)
          goto continue
        end
      end

      do
        local ok, err = raw_conn:consumeInput()
        if not ok then
          cqueues.cancel(poll_obj)
          raw_conn, errcount, stop = on_error(state, errcount + 1, err)
          goto continue
        end
      end

      local n = raw_conn:notifies()
      if not n then goto continue end

      local notif = Notification.new(n)
      local fns = state.handlers[notif.channel]
      if fns then
        for _, fn in ipairs(fns) do
          fn(notif)
          if notif._terminate then
            cqueues.cancel(poll_obj)
            state.connection:close()
            return
          end
        end
      end

      ::continue::
    end
  end
end

local DEFAULT_MAXERR = 3

local M = {}

function M.default_err_handler(conn, count, _, getconn)
  if count > DEFAULT_MAXERR then
    return
  end

  if conn then
    conn:close()
  end
  return (getconn())
end

function M.publish(chan, conn, msg)
  local payload = xerror.must(cjson.encode(msg))
  xerror.must(xerror.db(conn:query(SQL_PUBLISH, chan, payload)))
  return true
end

function M.subscribe(chan, f, state, cq)
  local fns = state.handlers[chan] or {}
  table.insert(fns, f)
  state.handlers[chan] = fns

  if #fns == 1 then
    -- first handler registered for this channel, must emit
    -- the LISTEN call.
    local conn = state.connection
    if not conn then
      -- first handler registered for pubsub, must get a
      -- long-lived connection.
      local err
      conn, err = state.connect()
      if not conn then
        return nil, err
      end
      state.connection = conn

      -- must start the coroutine that listens to notifications
      cq = cq or cqueues.running()
      xerror.must(cq, 'not running inside a cqueue coroutine')
      cq:wrap(make_notifier(state))
    end

    local ok, err = xerror.db(conn:exec(string.format(SQL_SUBSCRIBE, chan)))
    if not ok then
      return nil, err
    end
  end
  return true
end

return M
