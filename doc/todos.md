# list of todos

* Flash messages that persist across redirects
* User account/auth package (register, validate email, reset password, TOTP?)
* Non-web apps (e.g. message queue worker, log collector)
* Gzip middleware decoder for requests, encoder for responses

* Deployment script, with support for arbitrary staging environments and update of existing deploys (semi-done)
* Cohesive and consistent error handling (throw vs nil+msg)
* Easy to use HTTP client with circuit breaker support?
* I18n solution (not just text translation, but static assets too)
* Graceful shutdown with per-package hooks (semi-done with finalizers)
* A better way to check for package dependencies (e.g. checking for 'database' would not work if the config was under 'web.pkg.database').
* Test App composition, for both web and worker contexts
* Lua 5.4 and postgresql 13 (Fedora 33?)
