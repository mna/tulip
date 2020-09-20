local neturl = require 'net.url'

local Request = {__name = 'web.core.http.Request'}
Request.__index = Request

local M = {}

function M.new(stm, read_timeout)
  local hdrs = stm:get_headers(read_timeout)
  local path = hdrs:get(':path')
  local o = {
    stream = stm,
    authority = hdrs:get(':authority'),
    headers = hdrs,
    method = hdrs:get(':method'),
    rawurl = path,
    url = neturl.parse(path),
  }

  setmetatable(o, Request)
  return o
end

return M
