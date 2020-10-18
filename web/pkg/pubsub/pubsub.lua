local cjson = require('cjson.safe').new()
local cqueues = require 'cqueues'

local SQL_PUBLISH = [[
  SELECT
    pg_notify($1, $2)
]]

local SQL_SUBSCRIBE = [[
  LISTEN %q
]]

local Notification = {__name = 'web.pkg.pubsub.Notification'}
Notification.__index = Notification

local function new_notif(n)
  local o = {
    channel = n:relname(),
    payload = cjson.decode(n:extra()),
  }
  setmetatable(o, Notification)

  return o
end

local function make_notifier(state)
  local conn = state.connection._conn

  return function()
    while true do
      if cqueues.poll({pollfd = conn:socket(); events = "r"}) then
        if not conn:consumeInput() then
          -- TODO: might indicate it requires a new connection
        end

        local n = conn:notifies()
        if n then
          local notif = new_notif(n)
          local fns = state.handlers[notif.channel]
          if fns then
            for _, fn in ipairs(fns) do
              if fn(notif) then
                -- TODO: unregister that function
              end
            end
          end
        end
      end
    end
  end
end

local M = {}

function M.publish(chan, db, msg)
  local payload = assert(cjson.encode(msg))
  assert(db:query(SQL_PUBLISH, chan, payload))
  return true
end

function M.subscribe(chan, f, state)
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
      local cq = cqueues.running()
      assert(cq, 'not running inside a cqueue coroutine')
      cq:wrap(make_notifier(state))
    end

    local ok, err = conn:exec(string.format(SQL_SUBSCRIBE, chan))
    if not ok then
      return nil, err
    end
  end
  return true
end

return M
