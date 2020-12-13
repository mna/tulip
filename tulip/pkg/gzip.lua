local fn = require 'fn'
local tcheck = require 'tcheck'
local zlib = require 'zlib'

local function make_write_headers(res)
  local oldfn = res._write_headers
  return function(self, hdrs, eos, deadline)
    hdrs:upsert('content-encoding', 'gzip')
    hdrs:upsert('transfer-encoding', 'chunked')
    hdrs:delete('content-length')
    return oldfn(self, hdrs, eos, deadline)
  end
end

-- see https://stackoverflow.com/a/45221434/1094941
local GZIP_WINDOW_SIZE = 15 + 16

local function make_write_body(res, cfg)
  local oldfn = res._write_body

  return function(self, f, deadline)
    local gzip = zlib.deflate(cfg.level or 6, GZIP_WINDOW_SIZE)
    local compress = function(chunk, eos)
      return gzip(chunk, eos and 'finish' or 'sync')
    end

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

local function gzip_middleware(req, res, nxt, cfg)
  -- indicate that this response's content varies by Accept-Encoding
  res.headers:append('vary', 'Accept-Encoding')

  -- if this request does not accept gzip, bypass
  local ae = req.headers:get('accept-encoding') or ''
  if not string.find(ae, 'gzip') then -- TODO: more robust check
    return nxt()
  end

  -- it accepts gzip, install the modified res methods
  res._write_headers = make_write_headers(res)
  res._write_body = make_write_body(res, cfg)
  nxt()
end

local M = {
  requires = {
    'tulip.pkg.middleware',
  },
}

-- Package gzip registers a middleware that gzips the response
-- of the request if it accepts that encoding.
--
-- Requires: middleware package.
--
-- Config:
--
-- * level: number = compression level, 1(worst) to 9(best).
--
-- Middleware:
--
-- * tulip.pkg.gzip
--
--   Adds a vary by Accept-Encoding header to the response, and if the
--   request's Accept-Encoding accepts gzip, enables compression of the
--   response's body. Doing so will set the response's Content-Encoding
--   to gzip and Transfer-Encoding to chunked.
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app:register_middleware('tulip.pkg.gzip', fn.partialtrail(gzip_middleware, 3, cfg))
end

return M
