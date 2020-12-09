local lu = require 'luaunit'
local headers = require 'http.headers'
local Request = require 'web.pkg.server.Request'
local Response = require 'web.pkg.server.Response'

-- Stream mocks a lua-http Stream object for tests.
local Stream = {__name = 'test.Stream', connection = {version = 1.1}}
Stream.__index = Stream

function Stream:get_headers()
  return self._headers
end

function Stream.peername()
  return 'test', '127.0.0.1', 0
end

function Stream.localname()
  return 'test', '127.0.0.1', 0
end

function Stream.checktls()
  return false
end

function Stream:write_headers(hdrs, eos, to)
  if to and to < 0 then
    return nil, 'timed out'
  end

  if self._written then
    error('stream already written to')
  end
  self._written = {headers = hdrs:clone(), eos = eos}
  return true
end

function Stream:write_chunk(s, eos, to)
  if to and to < 0 then
    return nil, 'timed out'
  end

  if not self._written then
    error('stream headers were not written')
  end
  if self._written.eos then
    error('stream is closed')
  end
  self._written.body = (self._written.body or '') .. s
  self._written.eos = eos
  return true
end

function Stream:assertWritten(hdrs, body, eos)
  lu.assertIsTable(self._written)

  local t = self._written
  if hdrs then
    for k, want in pairs(hdrs) do
      local got = (t.headers:get(k)) or ''
      lu.assertEquals(got, want)
    end
  end
  if body then
    lu.assertEquals(t.body or '', body)
  end
  if eos ~= nil then
    lu.assertEquals(t.eos, eos)
  end
end

function Stream:get_next_chunk(to)
  -- read as chunks of 10
  return self:get_body_chars(10, to)
end

function Stream:get_body_as_string(to)
  if to and to < 0 then
    return nil, 'timed out'
  end

  return self._body
end

function Stream:get_body_chars(n, to)
  if to and to < 0 then
    return nil, 'timed out'
  end

  local start = self._body_start or 1
  local s = string.sub(self._body, start, start + n - 1)
  self._body_start = start + n
  if s == '' then return end
  return s
end

-- only supports until newline
function Stream:get_body_until(_, _, inc, to)
  if to and to < 0 then
    return nil, 'timed out'
  end

  local start = self._body_start or 1
  local ix = string.find(self._body, '\n', start, true)
  if not ix then
    -- pattern not found, return everything or nil if the body is consumed
    local s = string.sub(self._body, start)
    if s == '' then return end
    self._body_start = #self._body + 1
    return s
  else
    local last = ix
    if not inc then
      last = last - 1
    end
    local s = string.sub(self._body, start, last)
    self._body_start = ix + 1
    return s
  end
end

function Stream.new(method, path, body)
  local hdrs = headers.new()
  hdrs:append(':method', method)
  hdrs:append(':path', path)

  local o = {_headers = hdrs, _body = body}
  return setmetatable(o, Stream)
end

function Stream.newreqres(app, method, path, body)
  local stm = Stream.new(method, path, body)

  local req = Request.new(stm, 5)
  local res = Response.new(stm, 5)
  stm.request, stm.response = req, res
  req.app, res.app = app, app

  return stm, req, res
end

return Stream
