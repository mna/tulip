local cqueues = require 'cqueues'
local cookie = require 'http.cookie'
local neturl = require 'net.url'
local tcheck = require 'tcheck'
local xerror = require 'tulip.xerror'

local Request = {__name = 'tulip.pkg.server.Request'}
Request.__index = Request

-- Returns an iterator over the chunks of the body, with the read
-- timeout (if any) applied to reading the whole body (i.e. iterating
-- until the end). Throws an error if the body is already consumed.
function Request:body()
  if self.raw_body then
    xerror.throw('request body already consumed')
  end

  local to = self.read_timeout
  local deadline = to and (cqueues.monotime() + to)
  return function(stm)
    return stm:get_next_chunk(deadline and (deadline - cqueues.monotime()))
  end, self.stream
end

-- Reads the body based on the mode specified.
-- * if mode is a number, read and return up to n bytes
-- * if mode is "a", reads the whole body and returns it as a string,
--   and also sets req.raw_body field
-- * if mode is "l", read and return the next line, skipping eol
-- * if mode is "L", same as "l" but does not skip eol
--
-- On error, returns nil and an error message. If mode is "a" and
-- the raw_body field is set, returns it.
function Request:read_body(mode)
  local types = tcheck({'*', 'string|number'}, self, mode)

  if self.raw_body then
    if mode == 'a' then
      return self.raw_body
    end
    xerror.throw('request body already consumed')
  end

  local stm = self.stream
  if types[2] == 'number' then
    return xerror.io(stm:get_body_chars(mode, self.read_timeout))
  elseif mode == 'a' then
    local body, err = xerror.io(stm:get_body_as_string(self.read_timeout))
    if not body then
      return nil, err
    end
    self.raw_body = body
    return body
  elseif mode == 'l' then
    return xerror.io(stm:get_body_until('\n', true, false, self.read_timeout))
  elseif mode == 'L' then
    return xerror.io(stm:get_body_until('\n', true, true, self.read_timeout))
  else
    xerror.throw('invalid format character %q', mode)
  end
end

-- Decodes the body using the request's content-type or (if provided)
-- force_ct to determine the decoder to use, and returns the resulting
-- table. Also sets self.decoded_body field for future use, and returns
-- it if already set.
--
-- Note that this fully reads the body, so if Request:read_body wasn't
-- called yet, it will be called.
--
-- Returns nil, error on error.
function Request:decode_body(force_ct)
  if self.decoded_body then
    return self.decoded_body
  end

  local body, err = self:read_body('a')
  if not body then
    return nil, err
  end

  local decoded; decoded, err = self.app:decode(body, force_ct or self.headers:get('content-type'))
  if not decoded then
    return nil, err
  end

  self.decoded_body = decoded
  return decoded
end

function Request.new(stm, read_timeout)
  local hdrs = stm:get_headers(read_timeout)
  local path = hdrs:get(':path')

  local _, ip, port = stm:peername()
  if port then ip = ip .. ':' .. port end

  local auth = hdrs:get(':authority')
  local url = neturl.parse(path)
  if not url.host or url.host == '' then
    if auth and auth ~= '' then
      url:setAuthority(auth)
    end
    if not url.host or url.host == '' then
      url.host = hdrs:get('host')
    end
  end
  if not url.scheme or url.scheme == '' then
    if stm:checktls() then
      url.scheme = 'https'
    else
      url.scheme = 'http'
    end
  end

  local o = {
    stream = stm,
    remote_addr = ip,
    proto = stm.connection.version,
    authority = auth,
    headers = hdrs,
    cookies = cookie.parse_cookies(hdrs),
    method = hdrs:get(':method'),
    rawurl = path,
    url = url,
    read_timeout = read_timeout,
    locals = {},
  }

  return setmetatable(o, Request)
end

return Request
