local cjson = require 'cjson'
local headers = require 'http.headers'
local neturl = require 'net.url'

local Response = {__name = 'web.pkg.server.Response'}
Response.__index = Response

-- TODO: call app.encode or something like that (pluggable)
local function encode_body(ct, body)
  if ct == 'application/json' then
    return cjson.encode(body)
  elseif ct == 'application/x-www-form-urlencoded' then
    return neturl.buildQuery(body)
  else
    error(string.format('unsupported content-type to encode body: %s', ct))
  end
end

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

  local len
  local bodystr
  local hasbody = false
  if opts.body then
    local typ = type(opts.body)
    if typ == 'string' then
      bodystr = opts.body
      len = #bodystr
    elseif typ == 'table' then
      bodystr = encode_body(hdrs:get('content-type'), opts.body)
      len = #bodystr
    elseif typ == 'function' or io.type(opts.body) == 'file' then
      hdrs:upsert('transfer-encoding', 'chunked')
      hdrs:delete('content-length')
    else
      error(string.format('invalid type for body: %s', typ))
    end
    hasbody = true
  elseif opts.path then
    if opts.context then
      -- the path indicates a template to execute, which returns
      -- a string so once executed, the body is as if a string
      -- was passed and content-length is known.
      -- TODO: call app.render or something like that
      bodystr = template.process_file(opts.path, opts.context)
      len = #bodystr
    else
      hdrs:upsert('transfer-encoding', 'chunked')
      hdrs:delete('content-length')
    end
    hasbody = true
  else
    len = 0
  end

  if len then hdrs:upsert('content-length', tostring(len)) end

  assert(stm:write_headers(hdrs, ishead or not hasbody, timeout))
  if ishead or not hasbody then return end

  if bodystr then
    assert(stm:write_body_from_string(bodystr, timeout))
  else
    local bodyfile = opts.body
    local closefile = false
    if opts.path then
      bodyfile = assert(io.open(opts.path))
      closefile = true
    end

    if io.type(bodyfile) == 'file' then
      -- write from the file handle
      local ok, err = stm:write_body_from_file(bodyfile, timeout)
      if closefile then bodyfile:close() end
      assert(ok, err)
    else
      -- write in chunks
      for s in bodyfile() do
        assert(stm:write_chunk(s, false, timeout))
      end
      assert(stm:write_chunk('', true, timeout))
    end
  end
end

function Response.new(stm, write_timeout)
  local o = {
    headers = headers.new(),
    stream = stm,
    write_timeout = write_timeout,
  }
  setmetatable(o, Response)
  return o
end

return Response
