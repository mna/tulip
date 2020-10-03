local neturl = require 'net.url'
local tcheck = require 'tcheck'

local Request = {__name = 'web.pkg.server.Request'}
Request.__index = Request

function Request:body()
  if self.raw_body then
    error('request body already consumed')
  end

  local to = self.read_timeout
  return function(stm)
    return stm:get_next_chunk(to)
  end, self.stream
end

function Request:read_body(v)
  -- if v is a number, read up to n bytes, calls stream:get_body_chars(n, timeout)
  -- if v is "a", reads the whole body and returns it as a string, calls
  --   stream:get_body_as_string(timeout), also sets req.raw_body field
  -- if v is "l", reads the next line, skipping eol, calls stream:get_body_until(...)
  -- if v is "L", same as "l" but does not skip eol
  local types = tcheck({'*', 'string|number'}, self, v)

  if self.raw_body then
    error('request body already consumed')
  end

  local stm = self.stream
  if types[2] == 'number' then
    return stm:get_body_chars(v, self.read_timeout)
  elseif v == 'a' then
    local body = stm:get_body_as_string(self.read_timeout)
    self.raw_body = body
    return body
  elseif v == 'l' then
    return stm:get_body_until('\n', true, false, self.read_timeout)
  elseif v == 'L' then
    return stm:get_body_until('\n', true, true, self.read_timeout)
  else
    error(string.format('invalid format character %q', v))
  end
end

function Request:decode_body(force_ct)
  -- uses the request's content-type or (if provided) force_ct to determine
  -- how to decode the body, and returns the resulting table. Also sets
  -- self.decoded_body field for future use, so the idiom:
  --   local body = req.decoded_body or req:decode_body()
  -- can be used in middleware/handlers. Since it must read the full body,
  -- should also set raw_body (via calling req:read_body("a"))?
  -- Supports form-encoding, json, maybe xml, maybe pluggable.
  local body = self.raw_body or self:read_body('a')
  local decoded = self.app:decode(body, force_ct or self.headers:get('content-type'))
  self.decoded_body = decoded
  return decoded
end

function Request.new(stm, read_timeout)
  local hdrs = stm:get_headers(read_timeout)
  local path = hdrs:get(':path')
  local o = {
    stream = stm,
    authority = hdrs:get(':authority'),
    headers = hdrs,
    method = hdrs:get(':method'),
    rawurl = path,
    url = neturl.parse(path),
    read_timeout = read_timeout,
  }

  setmetatable(o, Request)
  return o
end

return Request
