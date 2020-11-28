local cookie = require 'http.cookie'
local crypto = require 'web.crypto'
local fn = require 'fn'
local xerror = require 'web.xerror'
local xtable = require 'web.xtable'

local MAX_COOKIE_LEN = 4096

local function save_b64_token_in_cookie(b64_tok, cfg, res)
  local encoded = crypto.encode(cfg.auth_key,
    b64_tok,
    cfg.cookie_name)
  if #encoded > MAX_COOKIE_LEN then return end

  local expiry = cfg.max_age
  if expiry then expiry = os.time() + expiry end

  local same_site = cfg.same_site
  -- lua-http does not support same-site none.
  if same_site and same_site == 'none' then same_site = nil end

  local ck = cookie.bake(cfg.cookie_name,
    encoded,
    expiry,
    cfg.domain,
    cfg.path,
    cfg.secure,
    cfg.http_only,
    same_site)
  res.headers:append('set-cookie', ck)
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

function M.signup(req, res, nxt, errh)
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
    return errh(req, res, nxt, err)
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

function M.check_session(req, res, nxt, cfg)
  local app = req.app
  local ck = req.cookies[cfg.cookie_name]
  if ck then
    local tok = read_b64_token_from_cookie(ck, cfg)
    if tok then
      local ok, err = app:token({
          type = 'session',
        })
    end
    -- TODO: validate that the session id (token) is still valid, get its account id.
    -- TODO: load the account corresponding to the token's ref_id
    -- req.locals.session_id = <token>
    -- req.locals.account = acct
  end

  nxt()
end

function M.logout(req, res, nxt)
  local ck = req.cookies['ssn']
  if ck then
    -- TODO: delete the session's token
    -- TODO: delete cookie on the response
  end
  req.locals.session_id = nil
  req.locals.account = nil
  nxt()
end

function M.delete(req, res, nxt)
  local app = req.app
  local acct = req.locals.account
  if not acct then
    -- error
  end

  -- TODO: decode_body can error
  local body = req.decoded_body or req:decode_body()
  local pwd = body.password or ''

  local ok, err = app:db(function(conn)
    assert(app:account(acct.id, pwd, conn))
    assert(acct:delete(conn))
    return true
  end)
  if not ok then
    -- error
  end

  -- TODO: clear session cookie and token
  req.locals.session_id = nil
  req.locals.account = nil

  nxt()
end

function M.setpwd(req, _, nxt)
  local app = req.app
  local acct = req.locals.account
  if not acct then
    -- error
  end

  -- TODO: decode_body can error
  local body = req.decoded_body or req:decode_body()

  local oldpwd = body.old_password or ''
  local newpwd, newpwd2 = body.new_password, body.new_password2
  if newpwd2 and newpwd ~= newpwd2 then
    -- error
  end

  -- validate old (current) password before changing
  local ok, err = app:db(function(conn)
    assert(app:account(acct.id, oldpwd, conn))
    assert(acct:change_pwd(newpwd, conn))
    return true
  end)
  if not ok then
    -- error
  end

  nxt()
end

function M.authz(req, res, nxt)
  local routeargs = req.routeargs
  if routeargs.allow or routeargs.deny then
    local acct = req.locals.account
    local acctset = xtable.toset(acct and acct.groups)
    local allowset = xtable.toset(routeargs.allow)

    -- TODO: if is in allowset, or allow * and acct exists, or allow ?
    -- then allow access.

    -- TODO: if not allowed by allowset, check if denied by denyset,
    -- otherwise allow access.
  end
  nxt()
end

return M
