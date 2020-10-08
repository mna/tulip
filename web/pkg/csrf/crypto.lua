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

return M
