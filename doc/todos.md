# list of todos

## high-priority

## up next

* Deployment script, with support for arbitrary staging environments and update of existing deploys (semi-done)
* Support multi-part forms/file uploads
* I18n (l10n) solution (not just text translation, but static assets too)
* Graceful shutdown with per-package hooks (semi-done with finalizers)
* Two-factor authentication, based on TOTP, with recovery codes.

## later/someday/maybe

* Easy to use HTTP client with circuit breaker support?
* Request header and body size limits (maybe even response body size)
* Test App composition, for both web and worker contexts
* Review structured log calls for consistency
* Webhook package? (inbound handler -> send to a queue, outbound manager -> async, handles retries)
