local M = {
  replaces = 'web.pkg.database',
  app = {
    register_migrations = function()
    end,
    lookup_migrations = function()
    end,
  },
}

function M.register(_, app)
  app.db = function()
  end
end

return M
