#!/usr/bin/env -S llrocks run

local handler = require 'tulip.handler'
local M = {}

if string.match(arg[0], '/minimal%.lua') then
  os.execute('./scripts/run_server.lua scripts.examples.minimal config')
  return
end

function M.config()
  return {
    log = { level = 'debug' },
    server = { host = '127.0.0.1', port = 0 },
    middleware = {
      'log',
      handler.write{ body = 'Hello, Tulip!' },
    },
  }
end

return M
