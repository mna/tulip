# list of todos

## high-priority

* User account/auth package
* General error handler mechanism for middleware, to avoid having to specify handlers for each package with middleware.
  - Maybe based on raised errors? And a recover that has a mux based on the middleware name and other things?

* Flash messages that persist across redirects (probably requires i18n solution)
* Cohesive and consistent error handling (throw vs nil+msg)

## up next

* Deployment script, with support for arbitrary staging environments and update of existing deploys (semi-done)
* Easy to use HTTP client with circuit breaker support?
* I18n solution (not just text translation, but static assets too)
* Graceful shutdown with per-package hooks (semi-done with finalizers)

## later/someday

* A better way to check for package dependencies (e.g. checking for 'database' would not work if the config was under 'web.pkg.database' - maybe the register function should store a string in a dict?).
* Test App composition, for both web and worker contexts
* Lua 5.4 and postgresql 13 (Fedora 33?)
* Review structured log calls for consistency
