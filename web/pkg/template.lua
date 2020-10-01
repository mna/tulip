local template = require 'resty.template'

local M = {}

local function make_render(tpl)
  return function(app, path, ctx)
    if not ctx.locals then
      ctx.locals = app.locals
    end
    return tpl.process_file(path, ctx)
  end
end

-- The template package registers an app:render method that uses
-- the lua-resty-template module.
function M.register(cfg, app)
  app.render = make_render(template.new{root = cfg.root_path})
end

return M
