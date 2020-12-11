local cjson = require 'cjson.safe'
local tcheck = require 'tcheck'

local JSON_MIME = 'application/json'

local function make_encoder(cfg)
  local enc = cjson.new()
  if cfg.allow_invalid_numbers == nil then
    cfg.allow_invalid_numbers = false
  end
  enc.encode_invalid_numbers(cfg.allow_invalid_numbers)
  if cfg.max_depth then
    enc.encode_max_depth(cfg.max_depth)
  end
  if cfg.number_precision then
    enc.encode_number_precision(cfg.number_precision)
  end
  if cfg.sparse_array then
    local arcfg = cfg.sparse_array
    enc.encode_sparse_array(arcfg.convert_excessive, arcfg.ratio, arcfg.safe)
  end
  return function(t, mime)
    if mime ~= JSON_MIME then return end
    return enc.encode(t)
  end
end

local function make_decoder(cfg)
  local dec = cjson.new()
  if cfg.allow_invalid_numbers == nil then
    cfg.allow_invalid_numbers = false
  end
  dec.decode_invalid_numbers(cfg.allow_invalid_numbers)
  if cfg.max_depth then
    dec.decode_max_depth(cfg.max_depth)
  end
  return function(s, mime)
    if mime ~= JSON_MIME then return end
    return dec.decode(s)
  end
end

local M = {}

-- The json package registers an encoder and a decoder that
-- handles the JSON format (application/json MIME type).
--
-- Config:
--
-- * encoder: table = a table with the following fields:
--   * allow_invalid_numbers: boolean = encode invalid numbers (infinity, NaN). Can
--     be set to the string "null" to encode as JSON null (default: false)
--   * max_depth: integer = maximum depth to allow (default: 1000)
--   * number_precision: integer = number of significant digits encoded (default: 14)
--   * sparse_array: table = table with fields convert_excessive, ratio and safe
--     (see https://www.kyne.com.au/~mark/software/lua-cjson-manual.html, default is
--     false, 2 and 10 respectively)
-- * decoder: table = a table with the following fields:
--   * allow_invalid_numbers: boolean = encode invalid numbers (infinity, NaN, hexadecimal)
--     (default: false)
--   * max_depth: integer = maximum depth to decode (default: 1000)
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)

  app:register_encoder('tulip.pkg.json', make_encoder(cfg.encoder or {}))
  app:register_decoder('tulip.pkg.json', make_decoder(cfg.decoder or {}))
end

return M
