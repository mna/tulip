local tcheck = require 'tcheck'
local template = require 'resty.template.safe'
local xerror = require 'tulip.xerror'
local xtable = require 'tulip.xtable'

local M = {}

local function make_render(tpl)
  return function(app, path, ctx)
    ctx = ctx or {}
    if ctx.locals == nil then
      ctx.locals = xtable.merge({}, app.locals)
    else
      ctx.locals = xtable.merge({}, app.locals, ctx.locals)
    end
    return xerror.inval(tpl.process_file(path, ctx))
  end
end

-- The template package registers an app:render method that uses
-- the lua-resty-template module.
--
-- Config:
--
-- * root_path: string = path to the root directory of templates
--
-- Method:
--
-- s, err = App:render(path, ctx)
--
--   Renders a template using the provided context.
--
--   > path: string = the path to the view, if a root_path was configured,
--     this is relative to that path.
--   > ctx: table = the context to execute the template. If the app.locals
--     field exist, it is added as ctx.locals, with any existing ctx.locals
--     values overriding the app's.
--   < s: string = the rendered template
--   < err: Error|nil = the error message if s is falsy
function M.register(cfg, app)
  tcheck({'table', 'tulip.App'}, cfg, app)
  app.render = make_render(template.new{root = cfg.root_path})
end

return M
