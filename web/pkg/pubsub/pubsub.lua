local cjson = require('cjson.safe').new()

local SQL_PUBLISH = [[
  SELECT
    pg_notify($1, $2);
]]

local M = {}

function M.publish(chan, db, msg)
  local payload = assert(cjson.encode(msg))
  assert(db:query(SQL_PUBLISH, chan, payload))
  return true
end

function M.subscribe(chan, f, handlers)
  local fns = handlers[chan] or {}
  table.insert(fns, f)
  handlers[chan] = fns
  -- TODO: if this is the first handler for this channel, must emit the LISTEN call
  return true
end

return M
