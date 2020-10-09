local hmac = require 'openssl.hmac'
local xio = require 'web.xio'

local function xor_token(a, b)
  assert(#a == #b, 'tokens to XOR must be of the same length')

  local c = {}
  for i = 1, #a do
    local ca, cb = string.byte(a, i), string.byte(b, i)
    table.insert(c, ca ~ cb)
  end
  return string.char(table.unpack(c))
end

local function verify_mac(h, v, mac)
  local mac2 = h:final(v)
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

-- Returns the unmasked token by splitting masked into the mask and
-- the xor'ed version, and then xor'ing again to get the raw version
-- of the token.
function M.unmask_token(masked_tok, len)
  if #masked_tok ~= 2 * len then return end
  local xord = string.sub(masked_tok, 1, len)
  local mask = string.sub(masked_tok, len + 1)
  return xor_token(mask, xord)
end

-- Decodes v from base64, validates the hmac authentication and
-- returns the raw token on success, nil on error.
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
  local h = hmac.new(hkey, 'sha256')
  if not verify_mac(h, table.concat(mac_vals, '|'), parts[3]) then
    return
  end

  -- verify date range
  local t1 = math.tointeger(parts[1])
  if not t1 then return end
  local t2 = os.time()
  if max_age > 0 and (t2 - t1) > max_age then return end

  return parts[2]
end

return M
