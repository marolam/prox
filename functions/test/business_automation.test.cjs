const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Business automation tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit'});
const db = admin.firestore();
const {businessAutomationJobId, businessAutomationReceiptId, syncBusinessAutomation,
  processBusinessAutomation, configureBusinessAutomation} = require('../lib/lib/business_automation_runner');
const consentId = (uid, leadId, channel) => createHash('sha256').update(JSON.stringify([uid, leadId, channel])).digest('hex');
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
  delete process.env.PROX_BUSINESS_AUTOMATION_OUTBOUND_ENABLED;
  delete process.env.PROX_SMS_WEBHOOK_URL;
  delete process.env.PROX_EMAIL_WEBHOOK_URL;
  delete process.env.PROX_BUSINESS_AUTOMATION_PROVIDER_TOKEN;
});
after(async () => { await admin.app().delete(); });

async function fixture({sourceId = 'source_a', channel = 'in_app', overrides = {}, enabled = true} = {}) {
  await db.doc('users/alice').set({displayName: 'Alice'});
  await db.doc('users/alice/billing/entitlements').set({businessPurchased: true, businessModeActive: true});
  await db.doc('users/alice/business/leads/items/lead_a').set({leadId: 'lead_a', status: 'new'});
  if (enabled) await db.doc('businessAutomation/config').set({enabled: true, outboundEnabled: false, providerIdempotency: false});
  const source = db.doc(`users/alice/business/automations/items/${sourceId}`);
  await source.set({leadId: 'lead_a', step: 'followup_15m', state: 'scheduled', channel,
    templateMessage: 'Suggested follow-up reply.', scheduledAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000), ...overrides});
  await syncBusinessAutomation(source.path);
  return {source, jobId: businessAutomationJobId(source.path),
    receiptId: businessAutomationReceiptId('alice', 'lead_a', 'followup_15m')};
}

async function outboundSetup(channel = 'sms') {
  process.env.PROX_BUSINESS_AUTOMATION_OUTBOUND_ENABLED = 'true';
  process.env.PROX_SMS_WEBHOOK_URL = 'https://provider.example.test/messages';
  process.env.PROX_EMAIL_WEBHOOK_URL = 'https://provider.example.test/messages';
  process.env.PROX_BUSINESS_AUTOMATION_PROVIDER_TOKEN = 'test-only-token';
  await db.doc('businessAutomation/config').set({enabled: true, outboundEnabled: true, providerIdempotency: true});
  await db.doc(`businessAutomationConsents/${consentId('alice', 'lead_a', channel)}`).set({uid: 'alice', leadId: 'lead_a', channel, allowed: true});
}

test('default configuration and future deadlines never dispatch or award reminders', async () => {
  const {jobId, source} = await fixture({enabled: false});
  let contacted = 0;
  const transport = async () => { contacted++; return true; };
  assert.equal(await processBusinessAutomation(jobId, {transport}), 'disabled');
  assert.equal((await source.get()).get('state'), 'scheduled');
  await db.doc('businessAutomation/config').set({enabled: true});
  await source.update({scheduledAt: admin.firestore.Timestamp.fromMillis(Date.now() + 60000)});
  await syncBusinessAutomation(source.path);
  assert.equal(await processBusinessAutomation(jobId, {transport}), 'future');
  assert.equal(contacted, 0);
  assert.equal((await db.collection('businessAutomationReceipts').get()).size, 0);
});

test('concurrent duplicate source documents create one genuine visible owner reminder', async () => {
  const first = await fixture();
  const second = await fixture({sourceId: 'old_random_duplicate'});
  let contacted = 0;
  const outcomes = await Promise.all([first.jobId, first.jobId, second.jobId].map(jobId =>
    processBusinessAutomation(jobId, {transport: async () => { contacted++; return true; }})));
  assert.equal(outcomes.filter(value => value === 'reminded').length, 1);
  assert.equal(contacted, 0);
  const events = await db.collection('users/alice/business/events/items').get();
  assert.equal(events.size, 1);
  assert.equal(events.docs[0].get('type'), 'business_followup_reminder');
  assert.equal(events.docs[0].get('deliveryMode'), 'owner_reminder');
  assert.equal((await db.doc('users/alice/business/leads/items/lead_a').get()).get('followupReminderMessage'), 'Suggested follow-up reply.');
  assert.equal((await db.doc(`businessAutomationReceipts/${first.receiptId}`).get()).get('state'), 'reminded');
  await first.source.update({state: 'scheduled', receiptId: 'forged', sentAt: admin.firestore.Timestamp.now()});
  await syncBusinessAutomation(first.source.path);
  assert.equal(await processBusinessAutomation(first.jobId), 'noop');
  assert.equal((await db.collection('businessAutomationReceipts').get()).size, 1);
});

test('unpaid, expired, inactive, missing or closed leads cannot produce follow-ups', async () => {
  for (const [name, setup] of [
    ['unpaid', () => db.doc('users/alice/billing/entitlements').set({businessModeActive: true})],
    ['expired', () => db.doc('users/alice/billing/entitlements').set({businessModeActive: true, businessSubscriptionActive: true,
      subscriptionRenewsAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1)})],
    ['inactive', () => db.doc('users/alice/billing/entitlements').update({businessModeActive: false})],
    ['missing', () => db.doc('users/alice/business/leads/items/lead_a').delete()],
    ['closed', () => db.doc('users/alice/business/leads/items/lead_a').set({status: 'responded'})],
  ]) {
    const {jobId} = await fixture({sourceId: name});
    await setup();
    assert.equal(await processBusinessAutomation(jobId), 'blocked', name);
  }
  assert.equal((await db.collection('businessAutomationReceipts').get()).size, 0);
});

test('cancellation, hard deletion, soft deletion and account markers stop stale queued work', async () => {
  for (const [name, change] of [
    ['cancelled', source => source.update({state: 'cancelled'})],
    ['hard', source => source.delete()],
    ['soft', source => source.update({deletedAt: admin.firestore.Timestamp.now()})],
    ['soft_boolean', source => source.update({deleted: true})],
  ]) {
    const {source, jobId} = await fixture({sourceId: name});
    await change(source);
    assert.equal(await processBusinessAutomation(jobId), 'cancelled');
    await syncBusinessAutomation(source.path);
    assert.equal(await processBusinessAutomation(jobId), 'noop');
  }
  const {source, jobId} = await fixture({sourceId: 'deleted_account'});
  await db.doc('accountDeletions/alice').set({status: 'complete'});
  assert.equal(await processBusinessAutomation(jobId), 'deleted');
  await source.update({state: 'scheduled'});
  await syncBusinessAutomation(source.path);
  assert.equal((await db.doc(`businessAutomationJobs/${jobId}`).get()).exists, false);
  assert.equal((await db.collection('businessAutomationReceipts').get()).size, 0);
});

test('exact source paths and known follow-up steps are enforced', async () => {
  assert.throws(() => businessAutomationJobId('foreign/alice/business/automations/items/fake'), /Invalid/);
  assert.throws(() => businessAutomationJobId('users/alice/business/automations/items/fake/nested/deeper'), /Invalid/);
  const {source, jobId} = await fixture({overrides: {step: 'spam_unbounded_step'}});
  assert.equal((await db.doc(`businessAutomationJobs/${jobId}`).get()).exists, false);
  await source.update({step: 'followup_15m', leadId: 'not/a/document'});
  await syncBusinessAutomation(source.path);
  assert.equal((await db.doc(`businessAutomationJobs/${jobId}`).get()).exists, false);
});

test('outbound requires every server configuration, consent and deployment safeguard', async () => {
  const {source, jobId} = await fixture({channel: 'sms'});
  let calls = 0;
  const transport = async () => { calls++; return true; };
  const retry = async () => { await source.update({state: 'scheduled', updatedAt: admin.firestore.Timestamp.now()}); await syncBusinessAutomation(source.path); };
  assert.equal(await processBusinessAutomation(jobId, {transport}), 'blocked');
  await outboundSetup();
  for (const change of [
    async () => { delete process.env.PROX_BUSINESS_AUTOMATION_OUTBOUND_ENABLED; },
    () => db.doc('businessAutomation/config').update({providerIdempotency: false}),
    () => db.doc(`businessAutomationConsents/${consentId('alice', 'lead_a', 'sms')}`).update({allowed: false}),
    async () => { process.env.PROX_SMS_WEBHOOK_URL = 'http://insecure.example.test'; },
    async () => { process.env.PROX_SMS_WEBHOOK_URL = 'https://127.0.0.1/private'; },
  ]) {
    await outboundSetup(); await change(); await retry();
    assert.equal(await processBusinessAutomation(jobId, {transport}), 'blocked');
  }
  assert.equal(calls, 0);
});

test('explicitly configured provider gets one stable idempotency key despite concurrent workers', async () => {
  const first = await fixture({channel: 'sms'});
  const second = await fixture({sourceId: 'old_duplicate', channel: 'sms'});
  await outboundSetup();
  const calls = [];
  const transport = async (url, payload, token) => { calls.push({url, payload, token}); return true; };
  await Promise.all([processBusinessAutomation(first.jobId, {transport}), processBusinessAutomation(second.jobId, {transport})]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].payload.idempotencyKey, first.receiptId);
  assert.equal(calls[0].token, 'test-only-token');
  assert.equal((await db.doc(`businessAutomationReceipts/${first.receiptId}`).get()).get('state'), 'sent');
  assert.equal((await db.collection('users/alice/business/events/items').get()).size, 1);
  // Either duplicate source can win the shared receipt. Settle a worker that
  // saw the active lease, then require both jobs to remain terminal on replay.
  for (const jobId of [first.jobId, second.jobId]) {
    const result = await processBusinessAutomation(jobId, {transport});
    assert.ok(['noop', 'deduplicated'].includes(result));
  }
  for (const jobId of [first.jobId, second.jobId]) {
    assert.equal(await processBusinessAutomation(jobId, {transport}), 'noop');
  }
  assert.equal(calls.length, 1);
  assert.equal((await db.collection('users/alice/business/events/items').get()).size, 1);
  assert.equal((await db.doc(`businessAutomationReceipts/${first.receiptId}`).get()).get('state'), 'sent');
});

test('ambiguous provider outcomes hold for review and never blindly resend', async () => {
  const {jobId, receiptId, source} = await fixture({channel: 'email'});
  await outboundSetup('email');
  let calls = 0;
  const transport = async () => { calls++; throw new Error('Timeout after uncertain provider acceptance.'); };
  assert.equal(await processBusinessAutomation(jobId, {transport}), 'review_required');
  assert.equal((await db.doc(`businessAutomationReceipts/${receiptId}`).get()).get('state'), 'review_required');
  await source.update({state: 'scheduled'}); await syncBusinessAutomation(source.path);
  assert.equal(await processBusinessAutomation(jobId, {transport}), 'noop');
  assert.equal(calls, 1);
  assert.equal((await db.collection('users/alice/business/events/items').get()).size, 0);
});

test('expired external leases require review without calling a provider again', async () => {
  const {jobId, receiptId} = await fixture({channel: 'sms'});
  await outboundSetup();
  await db.doc(`businessAutomationReceipts/${receiptId}`).set({uid: 'alice', state: 'dispatching',
    leaseToken: 'old_worker', leaseUntil: admin.firestore.Timestamp.fromMillis(Date.now() - 1)});
  await db.doc(`businessAutomationJobs/${jobId}`).update({state: 'processing'});
  let calls = 0;
  assert.equal(await processBusinessAutomation(jobId, {transport: async () => { calls++; return true; }}), 'review_required');
  assert.equal(calls, 0);
  assert.equal((await db.doc(`businessAutomationReceipts/${receiptId}`).get()).get('state'), 'review_required');
});

test('direct owner removal during provider delivery preserves dedup without recreating private user activity', async () => {
  const {jobId, receiptId} = await fixture({channel: 'sms'});
  await outboundSetup();
  let calls = 0;
  assert.equal(await processBusinessAutomation(jobId, {transport: async () => {
    calls++; await db.doc('users/alice').delete(); return true;
  }}), 'sent');
  assert.equal(calls, 1);
  assert.equal((await db.doc('users/alice').get()).exists, false);
  assert.equal((await db.collection('users/alice/business/events/items').get()).size, 0);
  assert.equal((await db.doc(`businessAutomationReceipts/${receiptId}`).get()).get('state'), 'sent');
  assert.equal(await processBusinessAutomation(jobId, {transport: async () => { calls++; return true; }}), 'noop');
  assert.equal(calls, 1);
});

test('only current non-deleted admin claims can explicitly configure automation', async () => {
  const data = {enabled: true, outboundEnabled: false, providerIdempotency: false};
  await assert.rejects(configureBusinessAutomation.run({data}), /Sign in/);
  await assert.rejects(configureBusinessAutomation.run({auth: {uid: 'alice', token: {}}, data}), /Administrator/);
  const auth = {uid: 'operator', token: {admin: true}};
  await assert.rejects(configureBusinessAutomation.run({auth, data: {...data, expectedUid: 'other'}}), /Account changed/);
  await assert.rejects(configureBusinessAutomation.run({auth, data: {...data, outboundEnabled: true}}), /idempotent provider/);
  const initial = await configureBusinessAutomation.run({auth, data: {expectedUid: 'operator'}});
  assert.equal(initial.enabled, false);
  assert.equal(initial.outboundDeploymentEnabled, false);
  assert.deepEqual(initial.providersConfigured, {sms: false, email: false});
  assert.equal((await db.doc('businessAutomation/config').get()).exists, false);
  const updated = await configureBusinessAutomation.run({auth, data});
  assert.equal(updated.enabled, true);
  assert.equal(updated.outboundEnabled, false);
  assert.equal((await db.doc('businessAutomation/config').get()).get('enabled'), true);
  await db.doc('accountDeletions/operator').set({status: 'complete'});
  await assert.rejects(configureBusinessAutomation.run({auth, data}), /being deleted/);
});
