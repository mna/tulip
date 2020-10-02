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

return M
