# Business follow-up operation

The worker ships disabled. Neither a deployment nor an existing SMS/email webhook environment variable enables customer messages by itself. No provider has been contacted during implementation or tests.

`configureBusinessAutomation` requires an authenticated, non-deleted account with the `admin: true` claim. An empty request (or only `expectedUid`) reads the effective configuration without changing it. A write must explicitly include all three booleans: `enabled`, `outboundEnabled`, `providerIdempotency`. Responses include those booleans plus `outboundDeploymentEnabled` and `providersConfigured: {sms, email}`. The admin operations UI can enable owner reminders while keeping outbound delivery off.

When `enabled` is true, a valid due `in_app` follow-up generates a reminder for the business owner, visible on the lead, plus a deterministic business activity event. It prepares suggested reply text; it does not claim that a customer has received a message. Preparing a reply template also leaves the lead's response status unchanged.

Each source document lives at `users/{uid}/business/automations/items/{id}`. The exact-path trigger maintains `businessAutomationJobs`; client submissions cannot provide trusted leases or receipts. New clients use deterministic lead/step IDs and retain original deadlines when retrying. Protected `businessAutomationReceipts` deduplicate older random source IDs by owner, lead and the three recognized steps. A completed step does not restart by rewriting an owner document. Owners can cancel pending sources even after their paid business access expires. Cancelled sources with no protected delivery receipt may be scheduled again explicitly.

Every delivery checks an existing owner, a non-deleting account, active business mode, a paid lifetime entitlement or an unexpired business subscription, and an existing open lead. Future deadlines, deleted leads, customer-response status and closed leads stop delivery. Owner reminder commits are atomic with their receipt. A changed source, missing lead or account deletion cannot recreate a user subtree. Account cleanup removes the protected jobs, receipts and consents by UID.

## Explicit customer delivery setup

Customer transport stays unavailable until all of the following have been configured separately by an operator:

- The admin configuration sets `enabled: true`, `outboundEnabled: true`, and `providerIdempotency: true`.
- The deployed worker environment explicitly sets `PROX_BUSINESS_AUTOMATION_OUTBOUND_ENABLED=true`.
- The requested channel has a trusted HTTPS `PROX_SMS_WEBHOOK_URL` or `PROX_EMAIL_WEBHOOK_URL`, with `PROX_BUSINESS_AUTOMATION_PROVIDER_TOKEN` supplied through managed secrets/environment configuration. URLs cannot carry credentials, redirects are rejected, and requests time out after ten seconds.
- A trusted consent integration has written a protected `businessAutomationConsents/{id}` document containing `uid`, `leadId`, `channel`, `allowed: true`, and no `revokedAt`. The document ID is SHA-256 of `JSON.stringify([uid, leadId, channel])`. These documents are inaccessible to client SDKs; an owner-supplied flag is not consent. Consent setup/verification remains an operator integration requirement; this change does not infer consent from a saved lead or an email/phone field.
- The provider guarantees idempotency for the supplied `Idempotency-Key` header and body `idempotencyKey`, and acknowledges with a successful JSON response `{accepted: true, idempotencyKey: "<same key>"}`. The body contains owner/lead/thread identifiers, step, channel and suggested message; a trusted provider resolves the consented recipient instead of trusting an arbitrary client destination.

The worker rechecks authorization, cancellation, current message, consent and account state immediately before contacting a provider. External delivery cannot be atomic with Firestore; an already accepted provider request cannot be recalled by a later cancellation. Transactions lease dispatches. An uncertain response, timeout, or expired dispatch lease moves the protected receipt and source to `review_required`; repeated scheduler runs do not resend it. An operator must reconcile the provider's idempotency record before deciding on recovery. No automatic receipt deletion or retry UI is supplied, since either could duplicate a customer message.

## Deployment and existing schedules

The exports are `onBusinessAutomationWritten`, `runBusinessFollowupAutomation`, and `configureBusinessAutomation`. The job query requires the checked-in `businessAutomationJobs` composite index for `state` and `scheduledAt`. The schedule checks the server configuration before doing work and processes bounded pages within a runtime deadline. Deployment alone does not modify the configuration.

Existing source documents predate the queue trigger. An explicit schedule action refreshes existing scheduled deterministic sources; older random schedules can be safely requeued by a trusted migration calling `syncBusinessAutomation` on their exact paths. The protected logical receipt prevents duplicate delivery. No production backfill or activation was performed as part of this implementation.

Local emulator tests cover concurrent duplicate schedules, paid/deleted account and lead guards, cancellation, default/future configuration, protected consent gates, stable provider idempotency, uncertain outcomes, expired leases and administrator authorization. Provider transport in tests is an injected local function; tests never send SMS or email.
