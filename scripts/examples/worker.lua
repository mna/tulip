#!/usr/bin/env -S llrocks run

local M = {}

if string.match(arg[0], '/worker%.lua') then
  os.execute('./scripts/run_server.lua scripts.examples.worker config')
  return
end

function M.config()
  return {
    log = { level = 'debug' },
    worker = {
      queues = {'a', 'b', 'c'},
    },
    mqueue = {},
    database = {
      connection_string = '',
    },
    wmiddleware = {'wroutes'},
    wroutes = {
      not_found = function(msg)
        local app = msg.app
        app:log('i', {msg = msg.payload})
      end,
    },
  }
end

return M
