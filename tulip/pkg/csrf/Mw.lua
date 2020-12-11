local crypto = require 'tulip.crypto'
local handler = require 'tulip.handler'
local neturl = require 'net.url'
local xerror = require 'tulip.xerror'
local xio = require 'tulip.xio'

local TOKEN_LEN = 32
local MAX_COOKIE_LEN = 4096

local SAFE_METHODS = {
  GET = true,
  HEAD = true,
  OPTIONS = true,
  TRACE = true,
}

local function default_fail(req, res)
  res:write{
    status = 403,
    body = 'Forbidden - ' .. req.locals.csrf_error,
    content_type = 'text/plain',
  }
end

local Mw = {__name = 'tulip.pkg.csrf.Mw'}
Mw.__index = Mw

function Mw:read_masked_token_from_request(req)
  -- first check the request header
  local encoded = req.headers:get(self.request_header)

  if (not encoded or encoded == '') and
    (req.headers:get('content-type') == 'application/x-www-form-urlencoded') then
    -- next the form input value
    local form = req:decode_body()
    if form then
      encoded = form[self.input_name]
    end
  end

  -- TODO: eventually, should also check into multipart fields
  if not encoded then return end
  return xio.b64decode(encoded)
end

function Mw:read_raw_token_from_cookie(req)
  local ck = req.cookies[self.cookie_name]
  if not ck or ck == '' then return end
  if #ck > MAX_COOKIE_LEN then return end
  local b64 = crypto.decode(self.auth_key,
    self.max_age,
    ck,
    self.cookie_name,
    req.locals.session_id or '-')
  return b64 and xio.b64decode(b64)
end

function Mw:save_raw_token_in_cookie(raw_tok, req, res)
  local encoded = crypto.encode(self.auth_key,
    xio.b64encode(raw_tok),
    self.cookie_name,
    req.locals.session_id or '-')
  if #encoded > MAX_COOKIE_LEN then return end

  handler.set_cookie(res, {
    name = self.cookie_name,
    value = encoded,
    ttl = self.max_age,
    domain = self.domain,
    path = self.path,
    insecure = not self.secure,
    allowjs = not self.http_only,
    same_site = self.same_site,
  })
  return true
end

function Mw:__call(req, res, nxt)
  -- TODO: allow skipping the check altogether?

  -- get the raw token from the cookie
  local raw_tok = self:read_raw_token_from_cookie(req)
  if not raw_tok or #raw_tok ~= TOKEN_LEN then
    -- consider any error retrieving the token (e.g. HMAC failure)
    -- as if the token was not there, and generate a new token.
    -- It will correctly fail validating any provided token.
    raw_tok = xio.random(TOKEN_LEN)

    -- store the new raw token in the cookie
    if not self:save_raw_token_in_cookie(raw_tok, req, res) then
      req.locals.csrf_error = 'failed to generate CSRF token'
      self.fail_handler(req, res, nxt)
      return
    end
  end

  -- get the masked, base64-encoded token for this request
  local cooked_tok = xio.b64encode(crypto.mask_token(raw_tok))
  req.locals.csrf_token = cooked_tok
  req.locals.csrf_input_name = self.input_name

  -- if the request is not for a safe method, validate the csrf
  -- token.
  if not SAFE_METHODS[req.method] then
    if req.url.scheme == 'https' then
      -- validate origin for https requests
      local referer = neturl.parse(req.headers:get('referer'))
      if (not referer.scheme or referer.scheme == '') or
        (not referer.host or referer.host == '') then
        req.locals.csrf_error = 'no referer'
        self.fail_handler(req, res, nxt)
        return
      end

      local here = req.url
      local valid = (here.scheme == referer.scheme and
        here.host == referer.host)
      if not valid and self.trusted_origins then
        for _, ori in ipairs(self.trusted_origins) do
          if referer.host == ori then
            valid = true
            break
          end
        end
      end

      if not valid then
        req.locals.csrf_error = 'invalid referer'
        self.fail_handler(req, res, nxt)
        return
      end
    end

    -- must have a non-empty raw token at this point, for non-idempotent
    -- requests.
    if not raw_tok or #raw_tok == 0 then
      req.locals.csrf_error = 'no CSRF token'
      self.fail_handler(req, res, nxt)
      return
    end

    -- unmask and decode the token received with the request
    local masked_tok = self:read_masked_token_from_request(req)
    if not masked_tok then
      req.locals.csrf_error = 'no CSRF token'
      self.fail_handler(req, res, nxt)
      return
    end
    local req_raw_tok = crypto.unmask_token(masked_tok, TOKEN_LEN)
    if raw_tok ~= req_raw_tok then
      req.locals.csrf_error = 'invalid CSRF token'
      self.fail_handler(req, res, nxt)
      return
    end
  end

  -- add vary by cookie to prevent caching the response
  res.headers:append('vary', 'Cookie')
  nxt()
end

function Mw.new(cfg)
  xerror.must(cfg.auth_key, 'csrf: authentication key is required')

  -- by default, set http-only and secure to true
  if cfg.http_only == nil then cfg.http_only = true end
  if cfg.secure == nil then cfg.secure = true end

  local o = {
    auth_key = cfg.auth_key,
    max_age = cfg.max_age or 3600 * 12,
    domain = cfg.domain,
    path = cfg.path,
    http_only = cfg.http_only,
    secure = cfg.secure,
    same_site = cfg.same_site or 'lax',
    request_header = cfg.request_header or 'x-csrf-token',
    input_name = cfg.input_name or '_csrf_token',
    cookie_name = cfg.cookie_name or 'csrf',
    fail_handler = cfg.fail_handler or default_fail,
    trusted_origins = cfg.trusted_origins,
  }
  return setmetatable(o, Mw)
end

return Mw
