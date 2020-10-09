local cqueues = require 'cqueues'
local headers = require 'http.headers'
local inspect = require 'inspect'
local posix = require 'posix'
local request = require 'http.request'
local server = require 'http.server'
local stdio = require 'posix.stdio'

local M = {}

function M.test_web_server()
  --[[
      print('>>>>> client read')
      local port = con:read('*l')
      print('>>>>> client done', port)
      cqueues.sleep(0.5)
      local req = request.new_from_uri(string.format('http://127.0.0.1:%s/', port))
      print('>>>>> client request created', req:to_uri())
      local hdrs, res = req:go(10)
      print('>>>> client got', hdrs, res)
      --print(hdrs:get(':status'))
      --print(res:get_body_as_string(10))
  ]]--


  --[[
  local pipe = assert(posix.popen(function()
    local srv = server.listen{
      host = '127.0.0.1',
      port = 0,
      reuseaddr = true,
      reuseport = true,
      onstream = function(_, stm)
        print('>>>>> server request received')
        local hdrs = headers.new()
        hdrs:upsert(':status', '200')
        print('>>>>> server headers set')
        local ok, msg = pcall(stm.write_headers, stm, hdrs, false)
        print('>>>>> server write headers done', ok, msg)
        stm:write_body_from_string('allo', 10)
      end,
    }
    assert(srv:listen())
    local _, _, port = srv:localname()
    io.write(port .. '\n')
    --print('>>>>> server will start')
    assert(srv:loop())
    --print('>>>>> server stopped')
    return 0
  end, 'r'))

  local pfd = assert(stdio.fdopen(pipe.fd, 'r'))
  local port = pfd:read('l')
  io.write(string.format('>>> got from spwan: %q\n' , port))
  --]]

    local req = request.new_from_uri('http://127.0.0.1:8880/hello')
    --print('>>>>> client request created', req:to_uri())
    local hdrs, res = req:go(10)
    print('>>>> client got', hdrs, res)
    print(hdrs:get(':status'))
    print(res:get_body_as_string(10))
end

return M
