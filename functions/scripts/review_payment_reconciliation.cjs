// Read-only operator queue. Never performs a refund or changes entitlement state.
const admin = require('firebase-admin');
const projectArg = process.argv.find(arg => arg.startsWith('--project='));
if (!projectArg) throw new Error('Pass --project=<firebase-project-id>. This command only reads the review queue.');
admin.initializeApp({projectId: projectArg.split('=')[1]});
(async () => {
  const queue = await admin.firestore().collection('paymentReconciliation').where('status', '==', 'review_required').get();
  const rows = queue.docs.map(doc => ({id: doc.id, ...doc.data()})).filter(row => row.operatorStatus !== 'resolved');
  console.log(JSON.stringify({pending: rows.length, events: rows.map(row => ({id: row.id, eventType: row.eventType, providerId: row.providerId, paymentId: row.paymentId, sessionId: row.sessionId, amountCents: row.amountCents, currency: row.currency, reason: row.reason, operatorAction: row.operatorAction, dueAt: row.dueAt}))}, null, 2));
  await admin.app().delete();
})().catch(error => {console.error(error.message); process.exitCode = 1;});
