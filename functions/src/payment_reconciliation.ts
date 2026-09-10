import * as admin from 'firebase-admin';
import {createHash} from 'node:crypto';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/** Only call after validating Square's signature on the original request bytes. */
export async function reconcileSquareLifecycle(payload: Record<string, any>): Promise<{status: string; reason: string}> {
  const eventType = String(payload.type || '');
  const isRefund = eventType === 'refund.created' || eventType === 'refund.updated';
  const object = payload.data?.object?.[isRefund ? 'refund' : 'dispute'] || {};
  const paymentId = String(object.payment_id || object.disputed_payment?.payment_id || '');
  const orderId = String(object.order_id || '');
  const providerId = String(object.id || payload.data?.id || '');
  const eventId = String(payload.event_id || '');
  if (!eventId || !providerId) throw new Error('missing_provider_event_identity');
  const eventKey = createHash('sha256').update(eventId).digest('hex');
  const objectKey = createHash('sha256').update(`${isRefund ? 'refund' : 'dispute'}:${providerId}`).digest('hex');
  const record = db.doc(`paymentReconciliation/${eventKey}`);
  const state = db.doc(`paymentProviderState/${objectKey}`);
  let registry = paymentId ? await db.collection('checkoutSessions').where('providerPaymentId', '==', paymentId).limit(1).get() : null;
  if ((!registry || registry.empty) && orderId) registry = await db.collection('checkoutSessions').where('providerOrderId', '==', orderId).limit(1).get();
  const registration = registry && !registry.empty ? registry.docs[0] : null;
  const uid = String(registration?.data()?.uid || '');
  const sessionId = registration?.id || '';
  const validIdentity = /^[A-Za-z0-9_-]{1,128}$/.test(uid) && /^[A-Za-z0-9_-]{1,128}$/.test(sessionId);
  return db.runTransaction(async tx => {
    const references = [record, state];
    if (validIdentity) references.push(db.doc(`users/${uid}/billing/externalCheckout/items/${sessionId}`), db.doc(`users/${uid}/billing/invoices/items/${sessionId}`), db.doc(`users/${uid}/billing/entitlements`), db.doc(`users/${uid}/meta/points`), db.doc(`accountDeletions/${uid}`));
    const [prior, previousState, session, invoice, entitlement, balance, deletion] = await tx.getAll(...references);
    if (prior.exists) return {status: String(prior.data()?.status), reason: String(prior.data()?.reason)};
    const now = admin.firestore.FieldValue.serverTimestamp();
    const providerStatus = String(object.status || object.state || 'UNKNOWN');
    const amountCents = Number(object.amount_money?.amount);
    const currency = String(object.amount_money?.currency || '');
    const version = Number(object.version || 0);
    let status = 'review_required';
    let reason = isRefund ? 'refund_not_completed' : 'dispute_requires_operator';
    let action = isRefund ? 'Verify the final refund status in Square before changing access.' : 'Review the dispute in Square and submit evidence before its due date.';
    const current = session?.data() || {};
    const ent = entitlement?.data() || {};
    const previousSource = String(current.previousSubscriptionSourceSessionId || '');
    const priorSourceSession = validIdentity && /^[A-Za-z0-9_-]{1,128}$/.test(previousSource) ? await tx.get(db.doc(`users/${uid}/billing/externalCheckout/items/${previousSource}`)) : null;
    const previous = previousState.data() || {};
    const complete = isRefund && providerStatus === 'COMPLETED';
    if ((version > 0 && Number(previous.version || 0) > version) || (previous.applied === true && !complete)) {
      status = 'ignored_stale'; reason = 'newer_provider_state_recorded'; action = 'No action required.';
    } else if (deletion?.exists) {
      status = 'review_required'; reason = 'account_deleted'; action = 'Reconcile the provider transaction without recreating account data.';
    } else if (!validIdentity || !session?.exists) {
      reason = 'session_unresolved'; action = 'Locate the payment in Square and map it to the original Prox receipt before applying any adjustment.';
    } else if (current.uid !== uid || current.provider !== 'square') {
      reason = 'session_identity_mismatch'; action = 'Verify the original server checkout identity before changing access.';
    } else if ((current.providerOrderId && current.providerOrderId !== orderId && isRefund) || (current.providerPaymentId && current.providerPaymentId !== paymentId)) {
      reason = 'payment_identity_mismatch'; action = 'Verify the refund payment/order identifiers against the original checkout.';
    } else if (isRefund && providerStatus !== 'COMPLETED') {
      reason = `refund_${providerStatus.toLowerCase()}`;
      action = ['FAILED', 'REJECTED'].includes(providerStatus) ? 'Confirm the failed refund with Square; do not revoke paid access.' : 'Wait for a completed refund event and verify provider status if it does not arrive.';
    } else if (!isRefund) {
      // Disputes may later be won, withdrawn or lost. Never infer a refund.
    } else if (currency !== 'USD' || !Number.isSafeInteger(amountCents) || amountCents <= 0 || amountCents !== Math.round(Number(current.amountUsd) * 100)) {
      reason = 'partial_or_mismatched_refund'; action = 'Review the partial amount, prior refunds and remaining access; apply an explicitly approved adjustment.';
      tx.update(session!.ref, {refundReviewRequired: true, updatedAt: now});
    } else if (current.refundReconciled === true || previous.applied === true) {
      status = 'already_reconciled'; reason = 'duplicate_completed_refund'; action = 'No action required.';
    } else {
      const sku = String(current.sku || '');
      let applied = false;
      if (!invoice?.exists) {
        applied = true; reason = 'refunded_before_grant';
      } else if (sku.startsWith('points_topup_')) {
        const points = Number(invoice.data()?.amountPoints || 0);
        const available = Number(balance?.data()?.currentPoints || 0);
        if (Number.isSafeInteger(points) && points > 0 && Number.isSafeInteger(available) && available >= points) {
          tx.set(balance!.ref, {currentPoints: available - points, totalPoints: Math.max(0, Number(balance?.data()?.totalPoints || 0) - points), updatedAt: now}, {merge: true});
          tx.create(balance!.ref.collection('events').doc(`refund_${sessionId}`), {eventId: `refund_${sessionId}`, category: 'purchase_refund', amount: -points, reason: 'Completed card refund', timestamp: now});
          applied = true; reason = 'points_reversed';
        } else {reason = 'refunded_points_already_spent'; action = 'Review spent points and dependent purchases; approve a debt or revocation policy before changing other access.';}
      } else if (sku === 'biz_onetime_unlock' && current.grantAddsLifetimeAccess === false) {
        tx.set(entitlement!.ref, {businessLifetimePaymentCount: Math.max(0, Number(ent.businessLifetimePaymentCount || 1) - 1), updatedAt: now}, {merge: true});
        applied = true; reason = 'duplicate_lifetime_payment_refunded';
      } else if (sku === 'biz_onetime_unlock' && Number(ent.businessLifetimePaymentCount || 1) > 1) {
        reason = 'lifetime_multiple_sources_requires_review'; action = 'Resolve the other paid lifetime receipts before removing access from this refunded source.';
      } else if (sku === 'biz_onetime_unlock' && current.grantAddsLifetimeAccess === true && ent.businessPurchasedSourceSessionId === sessionId) {
        const prepaid = ent.businessSubscriptionActive === true && ent.subscriptionRenewsAt instanceof admin.firestore.Timestamp && ent.subscriptionRenewsAt.toMillis() > Date.now();
        tx.set(entitlement!.ref, {businessPurchased: false, businessPurchasedSourceSessionId: admin.firestore.FieldValue.delete(), businessLifetimePaymentCount: 0, businessStoreUnlocked: prepaid, businessWalletUnlocked: prepaid, ...(!prepaid ? {businessModeActive: false} : {}), updatedAt: now}, {merge: true});
        applied = true; reason = 'matching_lifetime_access_revoked';
      } else if (sku === 'biz_monthly_subscription' && (priorSourceSession?.data()?.fullRefundConfirmed === true || priorSourceSession?.data()?.refundReviewRequired === true)) {
        reason = 'prior_prepaid_source_requires_review'; action = 'Reconcile the earlier refunded prepaid source before restoring or revoking the current period.';
      } else if (sku === 'biz_monthly_subscription' && ent.businessSubscriptionSourceSessionId === sessionId && current.grantedSubscriptionExpiresAt instanceof admin.firestore.Timestamp && ent.subscriptionRenewsAt instanceof admin.firestore.Timestamp && current.grantedSubscriptionExpiresAt.isEqual(ent.subscriptionRenewsAt)) {
        const priorExpiry = current.previousSubscriptionExpiresAt instanceof admin.firestore.Timestamp ? current.previousSubscriptionExpiresAt : null;
        const prepaid = priorExpiry !== null && priorExpiry.toMillis() > Date.now();
        const anyAccess = prepaid || ent.businessPurchased === true;
        tx.set(entitlement!.ref, {businessSubscriptionActive: prepaid, subscriptionRenewsAt: priorExpiry, businessSubscriptionSourceSessionId: current.previousSubscriptionSourceSessionId || admin.firestore.FieldValue.delete(), businessStoreUnlocked: anyAccess, businessWalletUnlocked: anyAccess, ...(!anyAccess ? {businessModeActive: false} : {}), updatedAt: now}, {merge: true});
        applied = true; reason = 'matching_prepaid_period_reversed';
      } else if (sku === 'dev_card_test_charge') {
        applied = true; reason = 'preview_refund_recorded';
      } else {reason = 'missing_or_superseded_entitlement_source'; action = 'Compare the original receipt with later purchases; revoke only the refunded source without removing unrelated access.';}
      if (applied) {
        status = 'reconciled'; action = 'No action required.';
        tx.update(session!.ref, {status: 'refunded', refundReconciled: true, refundId: providerId, refundReconciledAt: now, updatedAt: now});
        if (invoice?.exists) tx.update(invoice.ref, {status: 'refunded', refundId: providerId, refundedAt: now});
      }
      tx.update(session!.ref, {fullRefundConfirmed: true, refundReviewRequired: !applied, updatedAt: now});
    }
    if (status !== 'ignored_stale') tx.set(state, {version, providerStatus, applied: previous.applied === true || status === 'reconciled', updatedAt: now}, {merge: true});
    tx.create(record, {eventId, eventType, providerId, providerStatus, paymentId, orderId, uid: deletion?.exists ? '' : uid, sessionId, amountCents: Number.isFinite(amountCents) ? amountCents : null, currency, status, reason, operatorAction: action, dueAt: String(object.due_at || ''), createdAt: now, updatedAt: now});
    return {status, reason};
  });
}
