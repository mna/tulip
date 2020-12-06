local M = {
  replaces = 'web.pkg.database',
}

function M.register(_, app)
  app.db = function(app, f)
    if not f then
      return {}
    end
    return f({})
  end
end

return M
