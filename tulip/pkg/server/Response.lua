local cqueues = require 'cqueues'
local handler = require 'tulip.handler'
local headers = require 'http.headers'
local posix = require 'posix'
local xerror = require 'tulip.xerror'
local xstring = require 'tulip.xstring'
local xtable = require 'tulip.xtable'

local CHUNK_SIZE = 2^20 -- chunks of 1MB when writing from a file

local Response = {__name = 'tulip.pkg.server.Response'}
Response.__index = Response

-- Writes the headers. This function should not be called directly,
-- it exists for extensibility (e.g. gzip middleware) to intercept
-- writing headers before the write actually happens but after
-- Response:write has set all expected values. It should return
-- true on success, nil and an error message on error (it must not
-- throw).
--
-- * hdrs: the http headers instance to write
-- * eos: flag indicating if this is the end of the stream
-- * deadline: an absolute deadline time value from which a timeout will
--   be computed.
function Response:_write_headers(hdrs, eos, deadline)
  return xerror.io(self.stream:write_headers(hdrs, eos,
    deadline and (deadline - cqueues.monotime())))
end

-- Writes the body. This function should not be called directly,
-- it exists for extensibility (e.g. gzip middleware) to intercept
-- writing the raw body bytes as called from Response:write.
-- It should return the number of bytes written on success, nil
-- and an error message on error (it must not throw).
--
-- * f: function that returns two values on each call, the string
--   to write and a flag that indicates if this is the last chunk.
--   In case of errors it must return nil, err.
-- * deadline: an absolute deadline time value from which a timeout will
--   be computed for each written chunk.
function Response:_write_body(f, deadline)
  local stm = self.stream
  local n = 0

  while true do
    local s, eos = f()
    if not s then
      return nil, eos -- here, eos is an error
    end
    n = n + #s
    local ok, err = xerror.io(stm:write_chunk(s, eos,
      deadline and (deadline - cqueues.monotime())))
    if not ok then
      return nil, err
    end
    if eos then
      return n
    end
  end
end

-- High-level API to write a response, should not be mixed
-- with calls to the low-level stream object.
-- The opts table can have those fields:
-- * status (integer), defaults to 200.
-- * content_type (string), defaults to 'text/plain' if there's a body.
-- * body (string|table|function|file): if it is a table, gets
--   encoded based on the content_type and the registered encoders.
--   If there is no content-type or no known one, an error is returned.
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
      local cth = xstring.decode_header(hdrs:get('content-type') or '')
      local ct = #cth > 0 and cth[1].value or 'unknown'
      local s, err = self.app:encode(opts.body, ct)
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
      xerror.throw('invalid type for body: %s', typ)
    end
    hasbody = true
  elseif opts.path then
    if opts.context then
      -- the path indicates a template to execute, which returns
      -- a string so once executed, the body is as if a string
      -- was passed and content-length is known.
      local locals = xtable.merge({}, self.app.locals, stm.request.locals, opts.context.locals)
      local ctx = xtable.merge({}, opts.context)
      ctx.locals = locals
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
          bodystr = handler.HTTPSTATUS[404]
          len = #bodystr
        else
          return xerror.io(nil, err, code)
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

  local deadline = timeout and (cqueues.monotime() + timeout)
  do
    local ok, err = self:_write_headers(hdrs, ishead or not hasbody, deadline)
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
  local chunkfn
  if bodystr then
    chunkfn = function() return bodystr, true end
  elseif io.type(bodyfile) == 'file' then
    chunkfn = function()
      -- file:read returns nil on EOF (but no error)
      local s, err, errno = bodyfile:read(CHUNK_SIZE)
      if not s then
        if err then
          return xerror.io(nil, err, errno)
        end
        return '', true
      end
      return s
    end
  else
    local it, inv, var = bodyfile()
    local started = false
    chunkfn = function()
      if (not started) or (var ~= nil) then
        started = true
        var = it(inv, var)
      end
      if var == nil then
        return '', true
      end
      return var
    end
  end

  local n, err = self:_write_body(chunkfn, deadline)
  if closefile then bodyfile:close() end
  if not n then
    return nil, err, true
  end
  self.bytes_written = n
  return n
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
