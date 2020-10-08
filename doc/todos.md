# list of todos

* CSRF package: use gorilla/csrf as model, but add the session id to the hmac authentication of the csrf cookie to prevent further attacks (leverage luaossl hmac support)
* Token generation: use luaossl `rand.bytes(count)` (and seed at startup with `rand.ready()`)
* User account/auth package (register, validate email, reset password, TOTP?)
* Message queue
* Time series/metrics
* Pub/sub
* Cron/scheduled jobs
* Non-web apps (e.g. message queue worker, log collector)
* Gzip middleware decoder for requests, encoder for responses
* Deployment script, with support for arbitrary staging environments
