local lu = require 'luaunit'
local App = require 'web.App'
local Request = require 'web.pkg.server.Request'
local Response = require 'web.pkg.server.Response'
local Stream = require 'test.Stream'

local M = {}

function M.test_request()
  local app = App{
    server = {},
    middleware = {},
    json = {},
  }

  local newreq = function(method, path, body)
    local stm = Stream.new(method, path, body)
    local req = Request.new(stm, 5)
    stm.request = req
    req.app = app
    return req
  end

  -- Request:body iterator
  local req = newreq('GET', '/', 'abcdefghijklmnopqrstuvwxyz')
  local got = {}
  for s in req:body() do
    table.insert(got, s)
  end
  lu.assertEquals(got, {
    'abcdefghij',
    'klmnopqrst',
    'uvwxyz',
  })

  -- Request:body iterator with empty body
  req = newreq('GET', '/', '')
  got = {}
  for s in req:body() do
    table.insert(got, s)
  end
  lu.assertEquals(got, {})

  -- Request:read_body read all
  req = newreq('GET', '/', 'abcdefghijklmnopqrstuvwxyz')
  local s = req:read_body('a')
  lu.assertEquals(s, 'abcdefghijklmnopqrstuvwxyz')
  lu.assertEquals(s, req.raw_body)

  -- Request:body iterator after body is consumed
  lu.assertErrorMsgContains('already consumed', req.body, req)
  -- Request:read_body after body is consumed
  lu.assertErrorMsgContains('already consumed', req.read_body, req, 'l')

  -- Request:read_body number
  req = newreq('GET', '/', 'abcdefghijklmnopqrstuvwxyz')
  s = req:read_body(3)
  lu.assertEquals(s, 'abc')
  lu.assertNil(req.raw_body)

  -- Request:read_body line
  req = newreq('GET', '/', 'abcd\nefgh\nijkl')
  s = req:read_body('l')
  lu.assertEquals(s, 'abcd')
  lu.assertNil(req.raw_body)
  s = req:read_body('l')
  lu.assertEquals(s, 'efgh')
  s = req:read_body('l')
  lu.assertEquals(s, 'ijkl')
  s = req:read_body('l')
  lu.assertNil(s)

  -- Request:read_body Line
  req = newreq('GET', '/', 'abcd\nefgh\nijkl')
  s = req:read_body('L')
  lu.assertEquals(s, 'abcd\n')
  lu.assertNil(req.raw_body)
  s = req:read_body('L')
  lu.assertEquals(s, 'efgh\n')
  s = req:read_body('L')
  lu.assertEquals(s, 'ijkl')
  s = req:read_body('L')
  lu.assertNil(s)

  -- Request:read_body invalid mode
  req = newreq('GET', '/', 'abcdefghijkl')
  lu.assertErrorMsgContains('invalid format', req.read_body, req, 'z')

  -- Request:decode_body with default content-type
  req = newreq('GET', '/', '{"a": 1}')
  req.headers:upsert('content-type', 'application/json')
  local t = req:decode_body()
  lu.assertEquals(t, {a=1})
  lu.assertEquals(req.raw_body, '{"a": 1}')
  lu.assertEquals(t, req.decoded_body)

  -- Request:decode_body with forced content-type
  req = newreq('GET', '/', '{"a": 1}')
  req.headers:upsert('content-type', 'application/xml')
  t = req:decode_body('application/json')
  lu.assertEquals(t, {a=1})

  -- Request:decode_body without valid decoder
  req = newreq('GET', '/', '<x/>')
  req.headers:upsert('content-type', 'application/xml')
  lu.assertErrorMsgContains('no decoder', req.decode_body, req)
end

function M.test_response()
  local app = App{
    server = {},
    middleware = {},
    json = {},
    template = {root_path = 'test/testdata'}
  }

  local newres = function(method, path)
    local stm = Stream.new(method, path)
    local req = Request.new(stm, 5)
    local res = Response.new(stm, 5)
    stm.request, stm.response = req, res
    req.app, res.app = app, app
    return res
  end

  -- write empty table returns a code 200
  local res = newres('GET', '/')
  local n = res:write{}
  lu.assertEquals(n, 0)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = '',
    ['content-length'] = '0',
  }, '', true)

  -- write empty body with 204, does not write a content-length
  res = newres('GET', '/')
  n = res:write{status = 204}
  lu.assertEquals(n, 0)
  res.stream:assertWritten({
    [':status'] = '204',
    ['content-type'] = '',
    ['content-length'] = '',
  }, '', true)

  -- write a string
  res = newres('GET', '/')
  n = res:write{body = 'abc'}
  lu.assertEquals(n, 3)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = 'text/plain',
    ['content-length'] = '3',
  }, 'abc', true)

  -- write a table in json with explicit status
  res = newres('GET', '/')
  n = res:write{body = {a=1}, content_type = 'application/json', status = 201}
  lu.assertEquals(n, 7)
  res.stream:assertWritten({
    [':status'] = '201',
    ['content-type'] = 'application/json',
    ['content-length'] = '7',
  }, '{"a":1}', true)

  -- write a table in json but HEAD request
  res = newres('HEAD', '/')
  n = res:write{body = {a=1}, content_type = 'application/json'}
  lu.assertEquals(n, 0)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = 'application/json',
    ['content-length'] = '7',
  }, '', true)

  -- write a table with unsupported content type
  res = newres('GET', '/')
  lu.assertErrorMsgContains('no encoder', res.write, res, {body = {a=1}, content_type = 'application/xml'})

  -- write a function
  res = newres('GET', '/')
  n = res:write{body = function()
    return string.gmatch('abc def hij', '(%w+)')
  end}
  lu.assertEquals(n, 9)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = 'text/plain',
    ['content-length'] = '',
    ['transfer-encoding'] = 'chunked',
  }, 'abcdefhij', true)

  -- write a boolean, invalid type
  res = newres('GET', '/')
  lu.assertErrorMsgContains('invalid type', function()
    res:write{body = true}
  end)

  -- write a file
  res = newres('GET', '/')
  local err; n, err = res:write{path = 'test/testdata/file.txt'}
  lu.assertNil(err)
  lu.assertEquals(n, 4)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = 'text/plain',
    ['content-length'] = '',
    ['transfer-encoding'] = 'chunked',
  }, 'abcd', true)

  -- write a non-existing file
  res = newres('GET', '/')
  n, err = res:write{path = 'test/testdata/nosuchfile'}
  lu.assertNil(err)
  lu.assertEquals(n, 9)
  res.stream:assertWritten({
    [':status'] = '404',
    ['content-type'] = 'text/plain',
    ['content-length'] = '9',
    ['transfer-encoding'] = '',
  }, 'Not Found', true)

  -- write a file handle
  local fd = io.open('test/testdata/file.txt')
  lu.assertNotNil(fd)
  res = newres('GET', '/')
  n, err = res:write{body = fd}
  lu.assertNil(err)
  lu.assertEquals(n, 4)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = 'text/plain',
    ['content-length'] = '',
    ['transfer-encoding'] = 'chunked',
  }, 'abcd', true)
  lu.assertEquals(io.type(fd), 'file') -- not closed
  fd:close()

  -- write a template
  res = newres('GET', '/')
  n, err = res:write{path = 'template.txt', context = {message = 'hello'}}
  lu.assertNil(err)
  lu.assertEquals(n, 6)
  res.stream:assertWritten({
    [':status'] = '200',
    ['content-type'] = 'text/plain',
    ['content-length'] = '6',
  }, 'hello\n', true)
end

return M
