# list of todos

## postgres-oriented

* Pub/sub
* Cron/scheduled jobs
* Time series/metrics

## web-oriented

* Flash messages that persist across redirects
* User account/auth package (register, validate email, reset password, TOTP?)
* Non-web apps (e.g. message queue worker, log collector)
* Gzip middleware decoder for requests, encoder for responses

## lower priority

* Deployment script, with support for arbitrary staging environments and update of existing deploys
* Cohesive and consistent error handling (throw vs nil+msg)
* Easy to use HTTP client with circuit breaker support?
* I18n solution (not just text translation, but static assets too)
