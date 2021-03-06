local cookie = require 'http.cookie'
local extmime = require 'tulip.handler.extmime'
local httpstatus = require 'tulip.handler.httpstatus'
local xerror = require 'tulip.xerror'
local xtable = require 'tulip.xtable'

local M = {
  -- List mapping well-known file extensions to MIME types.
  EXTMIME = extmime,
  -- Default MIME type when unknown.
  DEFAULTMIME = 'application/octet-stream',
  -- List mapping common HTTP status codes to standard status text.
  HTTPSTATUS = httpstatus,
}

-- Returns a handler that just calls Response:write with t and calls the
-- next middleware. Raises an error if Response:write fails.
function M.write(t)
  return function(_, res, nxt)
    xerror.must(res:write(t))
    nxt()
  end
end

-- Returns a handler that serves a directory based on the first
-- Request.pathargs argument, then calls the next middleware. Sets the
-- content-type based on some well-known file extensions.
-- Raises an error if Response:write fails.
function M.dir(path)
  if #path == 0 or path[-1] ~= '/' then
    path = path .. '/'
  end

  return function(req, res, nxt)
    local subpath = req.pathargs[1]
    local ext = string.match(subpath, '%.[^%.]+$')
    local ct = M.EXTMIME[ext] or M.DEFAULTMIME

    if #subpath > 0 and subpath[1] == '/' then
      subpath = string.sub(subpath, 2)
    end
    xerror.must(res:write{
      content_type = ct,
      path = path .. subpath,
    })
    nxt()
  end
end

-- Returns an HTTP error handler that accepts req, res, nxt, err and
-- dispatches handling to the function indicated by t, where t is a
-- table where keys are error codes (e.g. 'EINVALID') and values are
-- either error handlers (accepting req, res, nxt, err) or a number
-- that indicates the HTTP status code to return (the body will be
-- set to the default text of that status code).
--
-- If the error does not correspond to any of the defined error codes,
-- the handler at array position 1 is called (or if it's a number, it
-- is used as status code), or if it is not set, the error is thrown.
function M.errhandler(t)
  return function(req, res, nxt, err)
    -- check if there is a specific handler for that error code
    for k, h in pairs(t) do
      if xerror.is(err, k) then
        if type(h) == 'number' then
          xerror.must(res:write{status = h, body = M.HTTPSTATUS[h] or ''})
          return
        else
          return h(req, res, nxt, err)
        end
      end
    end

    -- use the default handler, or throw
    local f = t[1]
    if f then
      if type(f) == 'number' then
        xerror.must(res:write{status = f, body = M.HTTPSTATUS[f] or ''})
      else
        f(req, res, nxt, err)
      end
    else
      xerror.throw(err)
    end
  end
end

-- Returns a handler that recovers from an error raised in subsequent
-- middleware, and calls f with req, res and the error. Note that there is no
-- next function argument in the arguments to f.
function M.recover(f)
  return function(req, res, nxt)
    local ok, err = pcall(nxt)
    if not ok then
      f(req, res, err)
    end
  end
end

-- Returns a worker handler that recovers from an error raised in subsequent
-- wmiddleware, and calls f with msg and the error. Note that there is no next
-- function argument in the arguments to f.
function M.wrecover(f)
  return function(msg, nxt)
    local ok, err = pcall(nxt)
    if not ok then
      f(msg, err)
    end
  end
end

-- Starts a call to a chain of middleware, where mws is an array
-- of middleware functions. This calls the middleware at index i
-- with a next() function generated to call the following middleware,
-- ending with a call to last() if it is non-nil. If i is not provided,
-- it is set to 1.
function M.chain_middleware(mws, req, res, last, i)
  i = i or 1
  if i > #mws then
    if last then last() end
    return
  end
  local mw = mws[i]
  mw(req, res, function(newreq, newres)
    M.chain_middleware(mws, newreq or req, newres or res, last, i+1)
  end)
end

-- Starts a call to a chain of wmiddleware, where mws is an array
-- of wmiddleware functions. This calls the wmiddleware at index i
-- with a next() function generated to call the following wmiddleware,
-- ending with a call to last() if it is non-nil. If i is not provided,
-- it is set to 1.
function M.chain_wmiddleware(mws, msg, last, i)
  i = i or 1
  if i > #mws then
    if last then last() end
    return
  end
  local mw = mws[i]
  mw(msg, function(newmsg)
    M.chain_wmiddleware(mws, newmsg or msg, last, i+1)
  end)
end

-- Writes a cookie to the response. The cfg table may have the following
-- fields:
--
-- * name: string = name of the cookie
-- * value: string = value of the cookie, set to '' if missing
-- * ttl: number = time-to-live, do not set for a browser-session cookie,
--   set to negative to delete the cookie.
-- * domain: string = domain of the cookie
-- * path: string = path of the cookie
-- * insecure: boolean = allow sending cookie on http (defaults to
--   false, which is Secure)
-- * allowjs: boolean = if true, cookie can be accessed via javascript
--   (defaults to false, which is HttpOnly).
-- * same_site: string = set same-site constraint, can be 'strict',
--   'lax' or 'none'. Defaults to the browser's default behaviour (lax).
function M.set_cookie(res, cfg)
  cfg = xtable.merge({
    value = '',
  }, cfg)

  cfg.secure = (not cfg.insecure)
  cfg.http_only = (not cfg.allowjs)
  if cfg.same_site and cfg.same_site == 'none' then
    cfg.same_site = nil
  end
  if cfg.ttl then
    cfg.expiry = (cfg.ttl >= 0 and (os.time() + cfg.ttl) or -math.huge)
  end
  local ck = cookie.bake(cfg.name,
    cfg.value,
    cfg.expiry,
    cfg.domain,
    cfg.path,
    cfg.secure,
    cfg.http_only,
    cfg.same_site)
  res.headers:append('set-cookie', ck)
end

return M
