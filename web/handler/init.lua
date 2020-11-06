local extmime = require 'web.handler.extmime'

local M = {
  EXTMIME = extmime,
  DEFAULTMIME = 'application/octet-stream',
}

-- Returns a handler that just calls Response:write with t.
function M.write(t)
  return function(_, res, nxt)
    res:write(t)
    nxt()
  end
end

-- Serves a directory based on the first request.pathargs argument.
-- Sets the content-type based on some well-known file extensions.
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
    res:write{
      content_type = ct,
      path = path .. subpath,
    }
    nxt()
  end
end

-- Recovers from an error raised in subsequent middleware, and calls f
-- with req, res and the error. Note that there is no next function argument
-- in the arguments to f.
function M.recover(f)
  return function(req, res, nxt)
    local ok, err = pcall(nxt)
    if not ok then
      f(req, res, err)
    end
  end
end

-- Recovers from an error raised in subsequent wmiddleware, and calls f
-- with msg and the error. Note that there is no next function argument
-- in the arguments to f.
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
-- ending with a call to last() if it is non-nil.
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
-- ending with a call to last() if it is non-nil.
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

return M
