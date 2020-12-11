local fn = require 'fn'
local handler = require 'tulip.handler'
local neturl = require 'net.url'
local tcheck = require 'tcheck'
local xtable = require 'tulip.xtable'

local function flash_method(req, ...)
  local new = table.pack(...)
  local flashes = req._flash or {}
  for i = 1, new.n do
    local v = new[i]
    if type(v) ~= 'table' then
      -- ensure all stored values are tables
      v = {__ = tostring(v)}
    end
    table.insert(flashes, v)
  end
  req._flash = flashes
  return true
end

local function load_flashes(req, cfg)
  local ck = req.cookies[cfg.cookie_name]
  if ck then
    local t = neturl.parseQuery(ck)

    -- transform the decoded table to an array, and transformed string
    -- messages back to strings
    local flashes = {}
    for k, v in pairs(t) do
      local i = tonumber(k)
      if i and i > 0 then
        local first, msg = next(v)
        if first == '__' and (not next(v, first)) then
          v = msg
        end
        flashes[i] = v
        if flashes.n and i > flashes.n then
          flashes.n = i
        end
      end
    end

    return flashes
  end
end

local function make_write_headers(req, res, cfg)
  local oldfn = res._write_headers
  return function(self, hdrs, eos, deadline)
    local v, ttl = nil, -1
    if req._flash and #req._flash > 0 then
      ttl = nil
      v = neturl.buildQuery(req._flash)
    end
    handler.set_cookie(res, {
      name = cfg.cookie_name,
      value = v,
      ttl = ttl,
      domain = cfg.domain,
      path = cfg.path,
      insecure = not cfg.secure,
      allowjs = not cfg.http_only,
      same_site = cfg.same_site,
    })
    return oldfn(self, hdrs, eos, deadline)
  end
end

local function flash_middleware(req, res, nxt, cfg)
  -- load existing flashes
  req.locals.flash = load_flashes(req, cfg)
  req.flash = flash_method

  -- install the modified res method, to write the flash messages'
  -- cookie before sending the response.
  res._write_headers = make_write_headers(req, res, cfg)

  nxt()
end

local CFGDEFAULTS = {
  cookie_name = 'flash',
  secure = true,
  http_only = true,
  same_site = 'lax',
}

local M = {
  requires = {
    'tulip.pkg.middleware',
  },
}

-- The flash package adds flash message support to the App.
--
-- Requires: the middleware package.
--
-- Config:
--  * cookie_name: string = name of the cookie holding the messages
--    (default: 'flash')
--  * domain: string = domain of the flash cookie (default: not set)
--  * path: string = path of the flash cookie (default: not set)
--  * secure: boolean = secure flag of the flash cookie (default: true)
--  * http_only: boolean = http-only flag of the flash cookie (default:
--    true)
--  * same_site: string = same-site flag of the flash cookie (default:
--    'lax')
--
-- Methods:
--
-- ok, err = Request:flash(...)
--
--   Adds flash messages to be stored for the next request. Flash messages
--   are (short) feedback messages that are generated in one request, but only
--   used in a subsequent request (e.g. following an account creation, after
--   a redirect to the login page, the "account created, please login" message
--   could be displayed). To that end, the flash messages are stored in a
--   session cookie by the middleware registered with this package.
--
--   > ...: table|string = the message(s) to add, will be url-encoded in the cookie.
--   < ok: boolean = true on success
--   < err: Error|nil = if v is falsy, the error message.
--
-- Middleware:
--
-- * tulip.pkg.flash
--
--   Must be added before any handler that writes the response and any handler
--   that uses existing flash messages. Available flash messages for a request
--   (that is, flash messages that were added in a previous request) are stored
--   on req.locals.flash. Messages added by Request:flash will be stored in a
--   cookie before the response is written.
--
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  local mwcfg = xtable.merge({}, CFGDEFAULTS, cfg)
  app:register_middleware('tulip.pkg.flash', fn.partialtrail(flash_middleware, 3, mwcfg))
end

return M
