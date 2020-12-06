local tcheck = require 'tcheck'
local zlib = require 'http.zlib'

local function make_write_headers(res)
  local oldfn = res._write_headers
  return function(self, hdrs, eos, deadline)
    hdrs:upsert('content-encoding', 'gzip')
    hdrs:upsert('transfer-encoding', 'chunked')
    hdrs:delete('content-length')
    return oldfn(self, hdrs, eos, deadline)
  end
end

local function make_write_body(res)
  local oldfn = res._write_body

  return function(self, f, deadline)
    local compress = zlib.deflate()
    -- wrap f so that it returns compressed chunks
    local newf = function()
      local s, eos = f()
      if not s then
        return nil, eos
      end
      local z = compress(s, eos)
      return z, eos
    end
    return oldfn(self, newf, deadline)
  end
end

local function gzip_middleware(req, res, nxt)
  -- indicate that this response's content varies by Accept-Encoding
  res.headers:append('vary', 'Accept-Encoding')

  -- if this request does not accept gzip, bypass
  local ae = req.headers:get('accept-encoding') or ''
  if not string.find(ae, 'gzip') then -- TODO: more robust check
    return nxt()
  end

  -- it accepts gzip, install the modified res methods
  res._write_headers = make_write_headers(res)
  res._write_body = make_write_body(res)
  nxt()
end

local M = {
  requires = {
    'web.pkg.middleware',
  },
}

-- Package gzip registers a middleware that gzips the response
-- of the request if it accepts that encoding.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app:register_middleware('web.pkg.gzip', gzip_middleware)
end

return M
