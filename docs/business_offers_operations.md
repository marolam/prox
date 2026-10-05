# Local offers operations

Business HQ → Post an offer and Storefront → Deals and local offers manage real owner offers. Settings → Local offers → Browse works for signed-in Personal and Pro users. Creating or editing requires active paid Pro access and the existing Pro rollout gate. A lapsed owner can still pause or delete existing offers.

An owner may keep 20 saved offers in total and at most 5 live publications. Owner edits and submissions are capped at 100 per UTC day, including at most 20 new creations. Expiry must be at least one minute ahead and within 30 days. Editing a published offer immediately removes its publication; saving or requesting review never publishes automatically.

| Stored status | Meaning |
| --- | --- |
| `draft` | Private saved draft |
| `pending_review` | Waiting for human approval |
| `active` | Approved publication, subject to live access and audience checks |
| `rejected` | Private offer with a reviewer reason |
| `paused` | Publication withdrawn by its owner |

The UI labels an expired active offer as Expired. Delete removes the source and projection and retires the offer ID in a tombstone. Owner save, submit, pause and delete actions use stable request IDs and expected revisions. Identical retries replay the original result; changed payloads cannot reuse a receipt and stale edits cannot overwrite a newer review.

Marty, signed in with the administrator claim, opens Settings → Local offers → Review. The Review tab requires a Firebase `admin: true` claim; account email or owner-written profile fields grant no review permission. Read the description, terms, discount, broad service area, expiry and selected audience. Reject misleading or unsafe services, contact details, exact addresses, sensitive information and prohibited goods. The small automatic syntax checks do not constitute human moderation. Request changes with a reason of at least five characters or approve publication. Approval verifies current paid access and the five-live-offer cap again.

Private `businessOffers/{offerId}` records contain authenticated `uid`/`ownerUid`, title, description, terms, broad `locationLabel`, optional discount percent, `public`/`party` visibility, expiry, revision, status, moderation state/reason and server creation/update/review timestamps. Owners read their own records; administrators read the review queue. All writes go through the callables. Server-only `businessOfferRequests`, `businessOfferBudgets` and `businessOfferTombstones` store replay receipts, daily counters and retired IDs.

Only human approval creates the limited `publicBusinessOffers/{offerId}` projection. Customers cannot read that collection directly. `listPublicBusinessOffers` returns a bounded allowlist after checking the current approved canonical revision, active paid entitlement, owner deletion and blocks in both directions. Confirmed Party visibility requires mutual membership in both directions. Paging uses document IDs, needs no composite index and can return an empty filtered page with a continuation cursor.

Every offer expires within 30 days. Expired, blocked, unpaid or deleted-owner offers are excluded on the next customer fetch. Owners should refresh Browse to recheck live visibility. Offer text contains only public details intentionally supplied by its owner and reviewed by the operator; no structured private profile contact, precise location, private storefront settings or operator notes are projected. Storefront text can prefill editable owner fields but is never published automatically.

The five additive exports are `upsertBusinessOffer`, `changeBusinessOfferState`, `reviewBusinessOffer`, `listPublicBusinessOffers` and `onBusinessOfferAccountDeleted`. Their deployment and reviewed Firestore rules were verified on October 5, 2026; native app publication remains a separate step. The deletion trigger cleans private/public offers, budgets, action receipts and retired IDs when the existing account-deletion marker is written. Markers also block recreation and cached requests during deletion.

Offers do not guarantee geographic ranking, a precise Nearby radius or presence in a match card. Customers use the existing Nearby request/accept conversation and meetup flow; an offer does not bypass contact consent, sell a purchase, send a broadcast or automatically message a customer. Operators should use the supplied broad service area to judge whether the offer is useful locally.

Validation: 12 focused backend/rules tests passed; the complete backend regression passed 166/166. Eight Flutter repository tests cover form submission, retry IDs, moderation dialogs, expired-access removal and account isolation without production writes; final full-app validation and distribution status are tracked in [growth_release_readiness.md](growth_release_readiness.md).
