local headers = require 'http.headers'
local posix = require 'posix'
local xtable = require 'web.xtable'

local Response = {__name = 'web.pkg.server.Response'}
Response.__index = Response

-- high-level API to write a response, should not be mixed
-- with calls to the low-level stream object.
-- The opts table can have those fields:
-- * status (integer)
-- * content_type (string)
-- * body (string|table|function|file): if it is a table, gets
--   encoded as JSON or form-encoding, depending on content_type.
--   If there is no content-type or no known one, an error is raised.
--   If this is a function, it must return an iterator that
--   returns string chunks to write. If it is a file object,
--   behaves as path but does not close it when done sending.
-- * context (table): the context for the template specified in path.
-- * path (string): a path to a file to write in chunks. If a
--   context field is also present (even if empty), path is rendered as a
--   template with context passed to it.
--
-- If the request method was HEAD, no body gets written, but
-- it does get processed to compute the content-length.
--
-- Returns the number of body bytes written on success (which may be 0),
-- or nil and an error message. A third return value indicates if some
-- data (e.g. headers) was written before the failure, by returning true
-- in that case (falsy otherwise).
--
function Response:write(opts)
  local stm = self.stream
  local hdrs = self.headers
  local ishead = stm.request.method == 'HEAD'
  local timeout = self.write_timeout

  if opts.status then
    hdrs:upsert(':status', tostring(opts.status))
  elseif not hdrs:has(':status') then
    hdrs:append(':status', '200') -- defaults to 200
  end
  if opts.content_type then
    hdrs:upsert('content-type', opts.content_type)
  elseif not hdrs:has('content-type') and (opts.body or opts.path) then
    hdrs:append('content-type', 'text/plain')
  end

  local len, bodystr, bodyfile
  local hasbody, closefile = false, false
  if opts.body then
    local typ = type(opts.body)
    if typ == 'string' then
      bodystr = opts.body
      len = #bodystr
    elseif typ == 'table' then
      local s, err = self.app:encode(opts.body, hdrs:get('content-type'))
      if not s then
        return nil, err
      end
      bodystr = s
      len = #bodystr
    elseif typ == 'function' or io.type(opts.body) == 'file' then
      hdrs:upsert('transfer-encoding', 'chunked')
      hdrs:delete('content-length')
      bodyfile = opts.body
    else
      return nil, string.format('invalid type for body: %s', typ)
    end
    hasbody = true
  elseif opts.path then
    if opts.context then
      -- the path indicates a template to execute, which returns
      -- a string so once executed, the body is as if a string
      -- was passed and content-length is known.
      local ctx = xtable.merge({}, self.app.locals, stm.request.locals, opts.context.locals)
      local s, err = self.app:render(opts.path, ctx)
      if not s then
        return nil, err
      end
      bodystr = s
      len = #bodystr
    else
      local f, err, code = io.open(opts.path)
      if not f then
        if code and code == posix.ENOENT then
          -- render a 404, file does not exist
          hdrs:upsert(':status', '404')
          bodystr = 'not found'
          len = #bodystr
        else
          return nil, err
        end
      else
        bodyfile = f
        hdrs:upsert('transfer-encoding', 'chunked')
        hdrs:delete('content-length')
        closefile = true
      end
    end
    hasbody = true
  elseif hdrs:get(':status') ~= '204' then
    len = 0
  end

  if len then hdrs:upsert('content-length', tostring(len)) end
  do
    local ok, err = stm:write_headers(hdrs, ishead or not hasbody, timeout)
    if not ok then
      if closefile then bodyfile:close() end
      -- assume that maybe something got written to the socket, or
      -- nothing can be written (e.g. client closed)
      return nil, err, true
    end
    if ishead or not hasbody then
      if closefile then bodyfile:close() end
      return 0
    end
  end

  -- write the body
  if bodystr then
    local ok, err = stm:write_body_from_string(bodystr, timeout)
    if not ok then
      return nil, err, true
    end
    self.bytes_written = len
  else
    if io.type(bodyfile) == 'file' then
      -- write from the file handle
      -- TODO: how to get bytes writen in this case?
      local ok, err = stm:write_body_from_file(bodyfile, timeout)
      if closefile then bodyfile:close() end
      if not ok then
        return nil, err, true
      end
    else
      -- write in chunks
      for s in bodyfile() do
        local ok, err = stm:write_chunk(s, false, timeout)
        if not ok then
          return nil, err, true
        end
        self.bytes_written = self.bytes_written + #s
      end

      -- finish the stream
      local ok, err = stm:write_chunk('', true, timeout)
      if not ok then
        return nil, err, true
      end
    end
  end

  return self.bytes_written
end

function Response.new(stm, write_timeout)
  local o = {
    headers = headers.new(),
    stream = stm,
    write_timeout = write_timeout,
    bytes_written = 0,
  }
  return setmetatable(o, Response)
end

return Response
