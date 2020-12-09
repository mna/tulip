# list of todos

## high-priority

* Document in a quick reference table the methods, signatures, config options of each package. (started in Google Sheets)

## up next

* Deployment script, with support for arbitrary staging environments and update of existing deploys (semi-done)
* I18n solution (not just text translation, but static assets too)
* Graceful shutdown with per-package hooks (semi-done with finalizers)
* Two-factor authentication, based on TOTP, with recovery codes.

## later/someday/maybe

* Easy to use HTTP client with circuit breaker support?
* Request header and body size limits (maybe even response body size)
* Test App composition, for both web and worker contexts
* Review structured log calls for consistency
* Webhook package? (inbound handler -> send to a queue, outbound manager -> async, handles retries)
