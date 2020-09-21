local M = {}

-- Returns a handler that just calls Response:write with t.
function M.write(t)
  return function(_, res)
    res:write(t)
  end
end

local EXT_TO_MIME = {
  js = 'application/javascript',
  css = 'text/css',
  html = 'text/html',
  gif = 'image/gif',
  jpg = 'image/jpeg',
  jpeg = 'image/jpeg',
  png = 'image/png',
  svg = 'image/svg+xml',
}

-- Serves a directory based on the first request.pathargs argument.
-- Sets the content-type based on some well-known file extensions.
function M.dir(path)
  if #path == 0 or path[-1] ~= '/' then
    path = path .. '/'
  end

  return function(req, res)
    local subpath = req.pathargs[1]
    local ext = string.match(subpath, '%.([^%.]+)$')
    local ct = EXT_TO_MIME[ext]

    if #subpath > 0 and subpath[1] == '/' then
      subpath = string.sub(subpath, 2)
    end
    res:write{
      content_type = ct,
      path = path .. subpath,
    }
  end
end

return M
