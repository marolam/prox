const {beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Legacy support tests require the local emulator.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit', storageBucket: 'demo-prox-audit.appspot.com'});
const db = admin.firestore();
const {
  legacySupportTicketId, syncLegacySupport, backfillLegacySupportForOperator,
  backfillLegacySupport, LEGACY_SUPPORT_COLLECTIONS,
} = require('../lib/growth_legacy_support');
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
});
after(async () => { await admin.app().delete(); });

test('legacy collections project to stable owner-scoped canonical reports without financial fields', async () => {
  for (const collection of LEGACY_SUPPORT_COLLECTIONS) {
    const source = db.collection(collection).doc('same-source-id');
    await source.set({ownerUid: 'alice', uid: 'wrong-alias', subject: 'Earlier issue',
      description: 'The app stopped responding.', status: collection === 'support_tickets' ? 1 : 'open',
      createdAt: admin.firestore.Timestamp.fromMillis(1000), appVersion: '0.19.0', buildNumber: '26', platform: 'android',
      technicianId: 'operator', payoutGranted: true, payoutCredited: true, feedbackScore100: 88});
    const snapshot = await source.get();
    const result = await syncLegacySupport(collection, source.id);
    const ticket = (await db.doc(`supportTickets/${result.ticketId}`).get()).data();
    assert.equal(ticket.uid, 'alice');
    assert.equal(ticket.ownerUid, 'alice');
    assert.equal(ticket.sourceCollection, collection);
    assert.equal(ticket.sourceId, source.id);
    assert.equal(ticket.metadata.version, '0.19.0');
    assert.equal(ticket.metadata.build, '26');
    assert.equal(ticket.message, 'The app stopped responding.');
    assert.equal(ticket.createdAt.toMillis(), snapshot.createTime.toMillis());
    assert.equal(ticket.legacyReportedCreatedAt.toMillis(), 1000);
    assert.equal(ticket.workflow, 'growth');
    assert.equal(ticket.severity, 'P2');
    assert.equal('technicianId' in ticket, false);
    assert.equal('payoutGranted' in ticket, false);
    assert.equal('payoutCredited' in ticket, false);
    assert.equal((await source.get()).data().payoutGranted, true);
  }
  assert.equal((await db.collection('supportTickets').get()).size, 3);
});

test('concurrent retries and feedback scoring updates do not duplicate reports or erase triage', async () => {
  const source = db.doc('bugReports/report-a');
  await source.set({ownerUid: 'alice', title: 'Map jump', note: 'Nearby moved after resume.', status: 'open'});
  await Promise.all([syncLegacySupport('bugReports', 'report-a'), syncLegacySupport('bugReports', 'report-a')]);
  const ticketRef = db.doc(`supportTickets/${legacySupportTicketId('bugReports', 'report-a')}`);
  await ticketRef.update({status: 'resolved', category: 'ux', severity: 'P1', fixedVersion: '0.20.0', fixedBuild: '27',
    firstResponseAt: admin.firestore.Timestamp.now(), lastReply: 'Fixed in build 27.'});
  await ticketRef.collection('replies').doc('support_reply_a').set({uid: 'operator', author: 'support', message: 'Fixed in build 27.'});
  await source.update({feedbackScore100: 100, feedbackScoredAt: admin.firestore.Timestamp.now()});
  const noop = await syncLegacySupport('bugReports', 'report-a');
  assert.equal(noop.unchanged, true);
  await source.update({note: 'Nearby moved after resume, even with Wi-Fi.'});
  await syncLegacySupport('bugReports', 'report-a');
  const ticket = (await ticketRef.get()).data();
  assert.equal(ticket.status, 'resolved');
  assert.equal(ticket.category, 'ux');
  assert.equal(ticket.severity, 'P1');
  assert.equal(ticket.fixedBuild, '27');
  assert.equal(ticket.lastReply, 'Fixed in build 27.');
  assert.equal(ticket.message, 'Nearby moved after resume, even with Wi-Fi.');
  assert.equal((await ticketRef.collection('replies').get()).size, 1);
  assert.equal((await db.collection('supportTickets').get()).size, 1);
});

test('feedback owner operational claims cannot become support responses or fixed builds', async () => {
  await db.doc('feedback/report-a').set({uid: 'alice', text: 'A suggestion for clearer directions.', type: 'feedback',
    status: 'resolved', severity: 'P0', firstResponseAt: admin.firestore.Timestamp.now(), fixedVersion: '9.9.9', fixedBuild: '999'});
  const result = await syncLegacySupport('feedback', 'report-a');
  const ticket = (await db.doc(`supportTickets/${result.ticketId}`).get()).data();
  assert.equal(ticket.status, 'open');
  assert.equal(ticket.severity, 'P2');
  assert.equal(ticket.category, 'feature');
  assert.equal(ticket.firstResponseAt, undefined);
  assert.equal(ticket.fixedVersion, undefined);
  assert.equal(ticket.fixedBuild, undefined);
});

test('existing report ownership cannot transfer through changed aliases', async () => {
  const source = db.doc('feedback/report-a');
  await source.set({uid: 'alice', text: 'Alice private report.'});
  const original = await syncLegacySupport('feedback', 'report-a');
  await source.update({uid: 'bob', ownerUid: 'bob'});
  const result = await syncLegacySupport('feedback', 'report-a');
  assert.equal(result.ownerMismatch, true);
  assert.equal((await db.doc(`supportTickets/${original.ticketId}`).get()).data().uid, 'alice');
});

test('missing owners are skipped and deleted-account evidence cannot recreate reports', async () => {
  await db.doc('feedback/no-owner').set({text: 'No identity.'});
  assert.equal((await syncLegacySupport('feedback', 'no-owner')).projected, false);
  await db.doc('accountDeletions/alice').set({status: 'complete'});
  await db.doc('bugReports/deleted-user').set({ownerUid: 'alice', description: 'Earlier private report.'});
  await syncLegacySupport('bugReports', 'deleted-user');
  assert.equal((await db.collection('supportTickets').get()).empty, true);
});

test('hard and soft source deletion removes canonical reports and their conversations', async () => {
  for (const soft of [false, true]) {
    const sourceId = soft ? 'soft-report' : 'hard-report';
    const source = db.collection('feedback').doc(sourceId);
    await source.set({uid: 'alice', text: 'My earlier question.'});
    const result = await syncLegacySupport('feedback', sourceId);
    const ticketRef = db.doc(`supportTickets/${result.ticketId}`);
    await ticketRef.collection('replies').doc('user_reply_a').set({uid: 'alice', author: 'user', message: 'Private detail.'});
    if (soft) await source.update({deleted: true}); else await source.delete();
    await syncLegacySupport('feedback', sourceId);
    await syncLegacySupport('feedback', sourceId);
    assert.equal((await ticketRef.get()).exists, false);
    assert.equal((await ticketRef.collection('replies').get()).empty, true);
  }
});

test('stale triggers use current source data and canonical paths cannot recurse', async () => {
  await assert.rejects(syncLegacySupport('supportTickets', 'report-a'), /supported legacy/);
  const source = db.doc('support_tickets/report-a');
  await source.set({uid: 'alice', body: 'Newest report.', status: 2});
  const result = await syncLegacySupport('support_tickets', 'report-a');
  assert.equal((await db.doc(`supportTickets/${result.ticketId}`).get()).data().status, 'resolved');
  await source.delete();
  await syncLegacySupport('support_tickets', 'report-a');
  assert.equal((await db.doc(`supportTickets/${result.ticketId}`).get()).exists, false);
});

test('private attachment normalization excludes foreign paths and public URLs', async () => {
  await db.doc('feedback/report-a').set({uid: 'alice', text: 'Screenshots included.', attachmentPaths: [
    'supportAttachments/alice/support_12345/screenshot.png',
    'supportAttachments/bob/support_67890/screenshot.jpg',
    'https://example.com/public-private-photo.jpg'], screenshotUrl: 'https://example.com/public-private-photo.jpg'});
  const result = await syncLegacySupport('feedback', 'report-a');
  const ticket = (await db.doc(`supportTickets/${result.ticketId}`).get()).data();
  assert.deepEqual(ticket.attachmentPaths, ['supportAttachments/alice/support_12345/screenshot.png']);
  assert.equal(ticket.screenshotUrl, undefined);
});

test('bounded backfill cursor crosses collections and retry never duplicates reports', async () => {
  for (const collection of LEGACY_SUPPORT_COLLECTIONS) {
    for (const sourceId of ['report-a', 'report-b']) await db.collection(collection).doc(sourceId).set({uid: 'alice', text: 'Earlier report.', body: 'Earlier report.'});
  }
  const first = await backfillLegacySupportForOperator('operator', {limit: 2});
  assert.equal(first.processed, 2);
  assert.equal(first.done, false);
  const retry = await backfillLegacySupportForOperator('operator', {limit: 2});
  assert.equal(retry.projected, 0);
  assert.equal(retry.nextCursor, first.nextCursor);
  let cursor = first.nextCursor, processed = first.processed;
  while (cursor) {
    const page = await backfillLegacySupportForOperator('operator', {limit: 2, cursor});
    assert.ok(page.processed <= 2);
    processed += page.processed;
    cursor = page.nextCursor;
    if (page.done) assert.equal(cursor, null);
  }
  assert.equal(processed, 6);
  assert.equal((await db.collection('supportTickets').get()).size, 6);
  await assert.rejects(backfillLegacySupportForOperator('operator', {cursor: 'invalid'}), /cursor/);
});

test('backfill callable requires admin claims and rejects account switches or deleted administrators', async () => {
  await assert.rejects(backfillLegacySupport.run({data: {}}), /administrator/);
  await assert.rejects(backfillLegacySupport.run({auth: {uid: 'alice', token: {}}, data: {}}), /administrator/);
  await assert.rejects(backfillLegacySupport.run({auth: {uid: 'operator', token: {admin: true}}, data: {expectedUid: 'other'}}), /account changed/);
  await db.doc('accountDeletions/operator').set({status: 'complete'});
  await assert.rejects(backfillLegacySupport.run({auth: {uid: 'operator', token: {admin: true}}, data: {}}), /being deleted/);
});
