local hmac = require 'openssl.hmac'
local xerror = require 'web.xerror'
local xio = require 'web.xio'

local function xor_token(a, b)
  xerror.must(#a == #b, 'tokens to XOR must be of the same length')

  local c = {}
  for i = 1, #a do
    local ca, cb = string.byte(a, i), string.byte(b, i)
    table.insert(c, ca ~ cb)
  end
  return string.char(table.unpack(c))
end

local function create_mac(hkey, v)
  local h = hmac.new(hkey, 'sha256')
  return h:final(v)
end

local function verify_mac(hkey, v, mac)
  local mac2 = create_mac(hkey, v)
  return mac == mac2
end

local M = {}

-- Returns a new token that is masked with a unique random token.
-- The unique token used for masking is appended to the masked
-- token, so the return values is twice the size of the raw_tok.
--
-- This is to mitigate the BREACH attack (http://breachattack.com/#mitigations)
function M.mask_token(raw_tok)
  local mask_tok = xio.random(#raw_tok)
  return xor_token(mask_tok, raw_tok) .. mask_tok
end

-- Returns the unmasked token by splitting masked_tok into the mask and
-- the xor'ed version, and then xor'ing again to get the raw version
-- of the token.
function M.unmask_token(masked_tok, len)
  if #masked_tok ~= 2 * len then return end

  local xord = string.sub(masked_tok, 1, len)
  local mask = string.sub(masked_tok, len + 1)
  return xor_token(mask, xord)
end

-- Decodes v, validating the hmac authentication and
-- returns the token on success, nil on error. Note that the
-- returned token is base64-encoded (assuming it was when
-- encode was called, which it should).
function M.decode(hkey, max_age, v, ...)
  -- decode from base64
  local decoded = xio.b64decode(v)
  if not decoded then return end

  -- get parts, value is date|value|mac
  local parts = {}
  string.gsub(decoded, '([^|]+)', function(p)
    table.insert(parts, p)
  end)
  if #parts ~= 3 then return end

  -- verify MAC, to compute it prepend the extra values
  local mac_vals = {...}
  table.move(parts, 1, 2, #mac_vals + 1, mac_vals)
  if not verify_mac(hkey, table.concat(mac_vals, '|'), parts[3]) then
    return
  end

  -- verify date range
  local t1 = math.tointeger(parts[1])
  if not t1 then return end
  local t2 = os.time()
  if max_age > 0 and (t2 - t1) > max_age then return end

  -- the returned value itself is base64-encoded, so that the pipe separator
  -- is safe (cannot appear in the value).
  return parts[2]
end

-- Encodes v with an hmac authentication created using hkey and
-- returns the encoded token. Note that v should already be
-- base64-encoded.
function M.encode(hkey, v, ...)
  -- create MAC with the extra values, then the date and the encoded
  -- value.
  local mac_vals = {...}
  table.insert(mac_vals, tostring(os.time()))
  table.insert(mac_vals, v)
  local mac = create_mac(hkey, table.concat(mac_vals, '|'))

  local cooked_vals = {mac_vals[#mac_vals-1], mac_vals[#mac_vals], mac}
  return xio.b64encode(table.concat(cooked_vals, '|'))
end

return M
