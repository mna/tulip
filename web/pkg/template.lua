local tcheck = require 'tcheck'
local template = require 'resty.template'
local xtable = require 'web.xtable'

local M = {}

local function make_render(tpl)
  return function(app, path, ctx)
    ctx = ctx or {}
    if ctx.locals == nil then
      ctx.locals = xtable.merge({}, app.locals)
    else
      ctx.locals = xtable.merge({}, app.locals, ctx.locals)
    end
    return tpl.process_file(path, ctx)
  end
end

-- The template package registers an app:render method that uses
-- the lua-resty-template module. If the locals package is used,
-- the locals are automatically set on the context passed to the
-- render method - unless it already has a locals field.
function M.register(cfg, app)
  tcheck({'table', 'web.App'}, cfg, app)
  app.render = make_render(template.new{root = cfg.root_path})
end

return M
