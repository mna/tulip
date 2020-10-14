# list of todos

* Token package (one-time use, e.g. reset pwd, validate email)
* Email package (probably provider-specific, but through a generic `App:send_email` method)
* User account/auth package (register, validate email, reset password, TOTP?)
* Message queue
* Time series/metrics
* Pub/sub
* Cron/scheduled jobs
* Non-web apps (e.g. message queue worker, log collector)
* Gzip middleware decoder for requests, encoder for responses
* Deployment script, with support for arbitrary staging environments and update of existing deploys
* Easy to use HTTP client with circuit breaker support?
* Cohesive and consistent error handling
