local M = {}

-- Returns a handler that just calls Response:write with t.
function M.write(t)
  return function(_, stm)
    stm.response:write(t)
  end
end

-- Serves a directory based on the first request.pathargs argument.
-- Sets the content-type based on some well-known file extensions.
function M.dir(path)
  if #path == 0 or path[-1] ~= '/' then
    path = path .. '/'
  end

  return function(_, stm)
    local subpath = stm.request.pathargs[1]
    local ext = string.match(subpath, '%.([^%.]+)$')
    local ct

    if ext == 'js' then
      ct = 'application/javascript'
    elseif ext == 'css' then
      ct = 'text/css'
    elseif ext == 'html' then
      ct = 'text/html'
    elseif ext == 'gif' then
      ct = 'image/gif'
    elseif ext == 'jpg' then
      ct = 'image/jpeg'
    elseif ext == 'png' then
      ct = 'image/png'
    elseif ext == 'svg' then
      ct = 'image/svg+xml'
    end

    if #subpath > 0 and subpath[1] == '/' then
      subpath = string.sub(subpath, 2)
    end
    stm.response:write{
      content_type = ct,
      path = path .. subpath,
    }
  end
end

return M
