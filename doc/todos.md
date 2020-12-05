# list of todos

## high-priority

* Normalize connection variable name to `conn`, last arg when optional in App methods.
* Flash messages that persist across redirects (probably requires i18n solution)
* A better way to check for package dependencies (e.g. checking for 'database' would not work if the config was under 'web.pkg.database' - maybe the register function should store a string in a dict?).

## up next

* Deployment script, with support for arbitrary staging environments and update of existing deploys (semi-done)
* Easy to use HTTP client with circuit breaker support?
* I18n solution (not just text translation, but static assets too)
* Graceful shutdown with per-package hooks (semi-done with finalizers)
* Two-factor authentication, based on TOTP, with recovery codes.

## later/someday

* Request header and body size limits (maybe even response body size)
* Test App composition, for both web and worker contexts
* Lua 5.4 and postgresql 13 (Fedora 33?)
* Review structured log calls for consistency
