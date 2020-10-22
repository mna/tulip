local headers = require 'http.headers'

local Stream = {__name = 'test.Stream', connection = {version = 1.1}}
Stream.__index = Stream

function Stream:get_headers()
  return self._headers
end

function Stream:peername()
  return 'test', '127.0.0.1', 0
end

function Stream:localname()
  return 'test', '127.0.0.1', 0
end

function Stream:checktls()
  return false
end

function Stream:write_headers()
  return true
end

function Stream:write_continue()
end

function Stream:get_next_chunk()
end

function Stream:each_chunk()
end

function Stream:get_body_as_string()
  return ''
end

function Stream:get_body_chars()
  return ''
end

function Stream:get_body_until()
  return ''
end

function Stream:save_body_to_file()
  return true
end

function Stream:get_body_as_file()
  return nil, 'not mocked'
end

function Stream:unget()
end

function Stream:write_chunk()
  return true
end

function Stream:write_body_from_string()
  return true
end

function Stream:write_body_from_file()
  return true
end

function Stream:shutdown()
end

function Stream.new(method, path)
  local hdrs = headers.new()
  hdrs:append(':method', method)
  hdrs:append(':path', path)

  local o = {_headers = hdrs}
  setmetatable(o, Stream)
  return o
end

return Stream
