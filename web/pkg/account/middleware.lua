local crypto = require 'web.crypto'
local fn = require 'fn'
local handler = require 'web.handler'
local xerror = require 'web.xerror'
local xtable = require 'web.xtable'

local MAX_COOKIE_LEN = 4096

local function save_b64_token_in_cookie(b64_tok, cfg, res)
  local encoded = crypto.encode(cfg.auth_key,
    b64_tok,
    cfg.cookie_name)
  if #encoded > MAX_COOKIE_LEN then return end

  handler.set_cookie(res, {
    name = cfg.cookie_name,
    value = encoded,
    ttl = cfg.max_age,
    domain = cfg.domain,
    path = cfg.path,
    insecure = not cfg.secure,
    allowjs = not cfg.http_only,
    same_site = cfg.same_site,
  })
  return true
end

local function read_b64_token_from_cookie(ck, cfg)
  if not ck or ck == '' then return end
  if #ck > MAX_COOKIE_LEN then return end
  return crypto.decode(cfg.auth_key,
    cfg.max_age,
    ck,
    cfg.cookie_name)
end

local M = {}

-- TODO: potential configuration options:
-- * error handlers for each middleware
-- * login fail handler
-- * session cookie name
-- * session remember-me and token duration (TTL)

function M.signup(req, res, nxt, errh, failh)
  local app = req.app
  local body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local email = body.email
  local pwd, pwd2 = body.password, body.password2
  local groups = body.groups
  local ok; ok, err = xerror.inval((pwd2 or pwd) == pwd,
    'passwords do not match', 'password')
  if not ok then
    return failh(req, res, nxt, err)
  end
  local gnames
  if groups then
    gnames = fn.reduce(function(cumul, name)
      table.insert(cumul, name)
      return cumul
    end, {}, string.gmatch(groups, '[^,%s]+'))
  end

  local acct; acct, err = app:create_account(email, pwd, gnames)
  if not acct then
    return errh(req, res, nxt, err)
  end
  req.locals.account = acct

  nxt()
end

function M.login(req, res, nxt, errh, failh, cfg)
  local app = req.app
  local body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local email = body.email
  local pwd = body.password or '' -- ensure a pwd validation is always done
  local persist = (body.rememberme and body.rememberme ~= '')

  local acct; acct, err = app:account(email, pwd)
  if not acct then
    if xerror.is(err, 'EINVAL') then
      return failh(req, res, nxt, err)
    else
      return errh(req, res, nxt, err)
    end
  end
  req.locals.account = acct

  local tok; tok, err = app:token{
    type = 'session',
    ref_id = acct.id,
    max_age = cfg.session_ttl,
  }
  if not tok then
    return errh(req, res, nxt, err)
  end
  req.locals.session_id = tok

  -- store the token securely (signed) in a cookie
  -- TODO: if persist is false, make it a session cookie
  local ok; ok, err = xerror.inval(
    save_b64_token_in_cookie(tok, cfg, res), 'encoded cookie is too long')
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.check_session(req, res, nxt, errh, cfg)
  local app = req.app

  local ck = req.cookies[cfg.cookie_name]
  if ck then
    local tok = read_b64_token_from_cookie(ck, cfg)

    if tok then
      local ok, id_or_err = app:token({
        type = 'session',
      }, nil, tok)

      if ok then
        local acct, err = app:account(id_or_err)
        if not acct then
          return errh(req, res, nxt, err)
        end
        req.locals.session_id = tok
        req.locals.account = acct
      else
        -- getting the token failed - if this is a DB failure, treat as
        -- an error, otherwise if session is now invalid, continue as
        -- if it wasn't there.
        if not xerror.is(id_or_err, 'EINVAL') then
          return errh(req, res, nxt, id_or_err)
        end
      end
    end
  end

  nxt()
end

function M.logout(req, res, nxt, errh, cfg)
  local app = req.app

  local ck = req.cookies[cfg.cookie_name]
  if ck then
    local tok = read_b64_token_from_cookie(ck, cfg)

    if tok then
      -- delete the token
      local ok, err = app:token({
        type = 'session',
        delete = true,
      }, nil, tok)
      if (not ok) and (not xerror.is(err, 'EINVAL')) then
        return errh(req, res, nxt, err)
      end
    end

    -- delete the cookie
    handler.set_cookie(res, {
      name = cfg.cookie_name,
      ttl = -1,
      domain = cfg.domain,
      path = cfg.path,
      insecure = not cfg.secure,
      allowjs = not cfg.http_only,
      same_site = cfg.same_site,
    })
  end
  req.locals.session_id = nil
  req.locals.account = nil

  nxt()
end

function M.delete(req, res, nxt, errh, failh, cfg)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  local body; body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end
  local pwd = body.password or ''

  local ok; ok, err = app:db(function(conn)
    -- validate the password
    xerror.must(app:account(acct.id, pwd, conn))
    xerror.must(acct:delete(conn))
    return true
  end)
  if not ok then
    if xerror.is(err, 'EINVAL') then
      -- password failed/account invalid
      return failh(req, res, nxt, err)
    else
      return errh(req, res, nxt, err)
    end
  end

  -- clear session cookie and token
  if req.cookies[cfg.cookie_name] then
    handler.set_cookie(res, {
      name = cfg.cookie_name,
      ttl = -1,
      domain = cfg.domain,
      path = cfg.path,
      insecure = not cfg.secure,
      allowjs = not cfg.http_only,
      same_site = cfg.same_site,
    })
  end
  req.locals.session_id = nil
  req.locals.account = nil

  nxt()
end

function M.init_vemail(req, res, nxt, errh, cfg)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- generate a new base64-encoded token
  local tok; tok, err = app:token({
    type = 'vemail',
    ref_id = acct.id,
    max_age = cfg.token_max_age,
    once = true,
  })
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- hmac-encode it
  local encoded = crypto.encode(cfg.auth_key, tok, acct.email)
  local ok; ok, err = app:mqueue({
    max_attempts = cfg.max_attempts,
    max_age = cfg.queue_max_age,
    queue = cfg.queue,
  }, nil, {
    email = acct.email,
    encoded_token = encoded,
  })
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

-- TODO: single errh and function decides behaviour based on EINVAL?

function M.vemail(req, res, nxt, errh, cfg)
  local app = req.app

  local enc_tok, err = xerror.inval(req.url.query and req.url.query.t, 'no token')
  if not enc_tok then
    return errh(req, res, nxt, err)
  end
  local email; email, err = xerror.inval(req.url.query and req.url.query.email, 'no email')
  if not email then
    return errh(req, res, nxt, err)
  end

  -- hmac-decode the token
  local tok; tok, err = xerror.inval(crypto.decode(cfg.auth_key,
    cfg.token_max_age, enc_tok, email), 'invalid token')
  if not tok then
    return errh(req, res, nxt, err)
  end

  -- load the corresponding account
  local acct; acct, err = app:account(email)
  if not acct then
    return errh(req, res, nxt, err)
  end

  -- validate the token
  local ok; ok, err = app:token({
    type = 'vemail',
    ref_id = acct.id,
  }, nil, tok)
  if not ok then
    return errh(req, res, nxt, err)
  end

  -- all good, mark the email as verified
  ok, err = app:db(function(conn)
    return xerror.must(acct:verify_email(conn))
  end)
  if not ok then
    return errh(req, res, nxt, err)
  end

  nxt()
end

function M.setpwd(req, res, nxt, errh, failh)
  local app = req.app

  local acct, err = xerror.inval(req.locals.account, 'no current account')
  if not acct then
    return errh(req, res, nxt, err)
  end

  local body; body, err = req:decode_body()
  if not body then
    return errh(req, res, nxt, err)
  end

  local oldpwd = body.old_password or ''
  local newpwd, newpwd2 = body.new_password, body.new_password2
  local ok; ok, err = xerror.inval((newpwd2 or newpwd) == newpwd,
    'passwords do not match', 'password')
  if not ok then
    return failh(req, res, nxt, err)
  end

  -- validate old (current) password before changing
  ok, err = app:db(function(conn)
    xerror.must(app:account(acct.id, oldpwd, conn))
    xerror.must(acct:change_pwd(newpwd, conn))
    return true
  end)
  if not ok then
    if xerror.is(err, 'EINVAL') then
      return failh(req, res, nxt, err)
    else
      return errh(req, res, nxt, err)
    end
  end

  nxt()
end

function M.authz(req, res, nxt, denyh)
  local routeargs = req.routeargs
  if routeargs.allow or routeargs.deny then
    local allowset = xtable.toset(routeargs.allow)
    if allowset['?'] then
      -- ? means allow everyone, authenticated or not
      return nxt()
    end

    local acct = req.locals.account
    if acct and allowset['*'] then
      -- * means allow anyone authenticated
      return nxt()
    end
    if acct and acct.verified and allowset['@'] then
      -- @ means allow anyone authenticated and verified
      return nxt()
    end

    local acctset = xtable.toset(acct and acct.groups)
    local allowinter = xtable.setinter(allowset, acctset)
    if next(allowinter) then
      -- account has one allowed group, so it is allowed
      return nxt()
    end

    -- not allowed by allowset, check if denied by denyset.
    local denyset = xtable.toset(routeargs.deny)
    if denyset['?'] then
      -- deny access to everyone, authenticated or not
      return denyh(req, res, nxt)
    end
    if acct and denyset['*'] then
      -- deny access to anyone authenticated
      return denyh(req, res, nxt)
    end
    if acct and acct.verified and denyset['@'] then
      -- deny access to anyone authenticated and verified
      return denyh(req, res, nxt)
    end
    local denyinter = xtable.setinter(denyset, acctset)
    if next(denyinter) then
      -- account has one denied group, so deny access
      return denyh(req, res, nxt)
    end
  end
  nxt()
end

return M
