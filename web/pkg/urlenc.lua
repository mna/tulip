local neturl = require 'net.url'
local tcheck = require 'tcheck'

local URLENC_MIME = 'application/x-www-form-urlencoded'

local function encode(t, mime)
  if mime ~= URLENC_MIME then return end
  return neturl.buildQuery(t)
end

local function decode(s, mime)
  if mime ~= URLENC_MIME then return end
  return neturl.parseQuery(s)
end

local M = {}

-- The urlenc package registers an encoder and a decoder that
-- handles the url encoding format (application/x-www-form-urlencoded
-- MIME type).
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)

  app:register_encoder('web.pkg.urlenc', encode)
  app:register_decoder('web.pkg.urlenc', decode)
end

return M
