local neturl = require 'net.url'

local Request = {__name = 'web.core.http.Request'}
Request.__index = Request

function Request:body()
  -- TODO: iterator over body chunks, uses read_timeout and stream:get_next_chunk
end

function Request:read_body(v)
  -- if v is a number, read up to n bytes, calls stream:get_body_chars(n, timeout)
  -- if v is "a", reads the whole body and returns it as a string, calls stream:get_body_as_string(timeout), also sets req.raw_body field
  -- if v is "l", reads the next line, skipping eol, calls stream:get_body_until(...)
  -- if v is "L", same as "l" but does not skip eol
end

function Request:decode_body(force_ct)
  -- uses the request's content-type or (if provided) force_ct to determine
  -- how to decode the body, and returns the resulting table. Also sets
  -- self.decoded_body field for future use, so the idiom:
  --   local body = req.decoded_body or req:decode_body()
  -- can be used in middleware/handlers. Since it must read the full body,
  -- should also set raw_body (via calling req:read_body("a"))?
  -- Supports form-encoding, json, maybe xml, maybe pluggable.
end

local M = {}

function M.new(stm, read_timeout)
  local hdrs = stm:get_headers(read_timeout)
  local path = hdrs:get(':path')
  -- TODO: add content_type field?
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

return M
