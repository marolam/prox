const {before, beforeEach, after, test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc, updateDoc, collection, getDocs, query, orderBy} = require('firebase/firestore');
const {ref, uploadBytes, getBytes} = require('firebase/storage');
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_STORAGE_EMULATOR_HOST) throw new Error('Growth tests require Firestore and Storage emulators.');
if (!admin.apps.length) admin.initializeApp({projectId: 'demo-prox-audit', storageBucket: 'demo-prox-audit.appspot.com'});
const db = admin.firestore();
const growth = require('../lib/growth_ops');
const {claimReward} = require('../lib/verified_rewards');
const {syncLegacySupport, legacySupportTicketId} = require('../lib/growth_legacy_support');
const {eraseUserData} = require('../lib/account_lifecycle');
const {finalizeReferralSingleUseToken, referralApkDownload} = require('../lib/referral_downloads');
const {recordCompletedMeetup} = require('../lib/meetup_accounting');
const DAY = 86400000;
const timestamp = ms => admin.firestore.Timestamp.fromMillis(ms);
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-prox-audit', firestore: {
    host: '127.0.0.1', port: 8088, rules: readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
  }, storage: {host: '127.0.0.1', port: 9198, rules: readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8')}});
});
beforeEach(async () => {
  const response = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-prox-audit/databases/(default)/documents`, {method: 'DELETE'});
  assert.equal(response.status, 200);
  await db.doc('growthOps/config').set({...growth.DEFAULT_GROWTH_CONFIG, stage: 'referrals'});
});
after(async () => {await env?.cleanup(); await admin.app().delete();});

const completeProfile = {displayName: 'Tester', selfieUrl: 'https://example.test/selfie.jpg',
  keywords: {'Searching For': ['gardening'], 'Can Provide': ['cooking']}};
async function account(uid, complete = true, createdAt = Date.now()) {
  await db.doc(`users/${uid}`).set(complete ? completeProfile : {displayName: 'Incomplete'});
  await growth.ensureGrowthIdentity(uid, createdAt);
}
async function conversation(uid, peer = 'peer') {
  await db.doc(`users/${peer}`).set({displayName: 'Peer'});
  const chat = db.doc(`chats/${uid}_${peer}`);
  await chat.set({participants: [uid, peer], isGroup: false});
  await chat.collection('messages').doc().set({from: uid, to: peer, text: 'Hello there', kind: 'text', ts: timestamp(Date.now())});
  await chat.collection('messages').doc().set({from: peer, to: uid, text: 'Hello back', kind: 'text', ts: timestamp(Date.now())});
}
async function completedMeetup(uid, peer = 'peer') {
  await db.doc(`users/${peer}`).set({displayName: 'Peer'});
  const meetupId = `verified_${uid}_${peer}`;
  await db.doc(`meetups/${meetupId}`).set({
    aUid: uid, bUid: peer, status: 'completed', aArrived: true, bArrived: true,
    completedAt: timestamp(Date.now()),
  });
  await recordCompletedMeetup(meetupId, uid);
}
async function inviteFor(owner = 'owner', request = 'invite_request_0001', device = 'owner-device') {
  if (!(await db.doc(`users/${owner}`).get()).exists) await account(owner);
  return growth.createGrowthInviteForUid(owner, request, device, '192.0.2.1');
}
async function accept(uid, code, device = `device-${uid}`, ip = `192.0.2.${uid.length + 10}`) {
  await account(uid);
  return growth.acceptGrowthReferralForUid(uid, {code, deviceId: device}, ip);
}
function httpResponse() {
  return {statusCode: 200, body: null, url: null, status(code) {this.statusCode = code; return this;},
    json(value) {this.body = value;}, set() {}, redirect(code, url) {this.statusCode = code; this.url = url;}};
}

test('tester selection requires admin approval and concurrent approval cannot overbook the 20-person cohort', async () => {
  await db.doc('growthOps/config').update({testerCapacity: 10});
  for (let n = 0; n < 11; n++) {await account(`tester${n}`); await growth.joinTesterForUid(`tester${n}`);}
  assert.equal((await db.collection('growthMembers').get()).size, 0);
  assert.equal((await growth.growthStatusForUid('tester0')).tester.status, 'pending');
  const outcomes = await Promise.allSettled(Array.from({length: 11}, (_, n) => growth.reviewTesterForOperator('operator', {uid: `tester${n}`, decision: 'approve'})));
  assert.equal(outcomes.filter(row => row.status === 'fulfilled').length, 10);
  assert.equal((await db.doc('growthOps/cohort').get()).data().members.length, 10);
  assert.equal((await db.collection('growthMembers').get()).size, 10);
  assert.equal(growth.normalizeGrowthConfig({testerCapacity: 999}).testerCapacity, 20);
  const approved = (await db.collection('growthMembers').get()).docs[0];
  assert.equal(approved.data().deadline.toMillis() - approved.data().joinedAt.toMillis(), 48 * 3600000);
  assert.equal((await growth.reviewTesterForOperator('operator', {uid: approved.id, decision: 'approve'})).replayed, true);
});

test('the rollout gate and kill switch stop invites, enrollment and telemetry writes', async () => {
  await account('owner');
  await db.doc('growthOps/config').update({stage: 'testers'});
  await assert.rejects(growth.createGrowthInviteForUid('owner', 'invite_stage_0001'), /first tester stage/);
  await db.doc('growthOps/config').update({enabled: false});
  await assert.rejects(growth.joinTesterForUid('owner'), /paused/);
  assert.equal((await growth.recordGrowthSessionForUid('owner', {sessionId: 'session_disabled', event: 'start'})).recorded, false);
});

test('invite and welcome grants remain idempotent under concurrency, with server invite budgets', async () => {
  await account('owner');
  await db.doc('growthOps/config').update({maxInvitesPerDay: 1});
  const issued = await Promise.all([inviteFor(), inviteFor()]);
  assert.equal(issued[0].code, issued[1].code);
  assert.equal((await db.collection('growthInvites').get()).size, 1);
  assert.match(issued[0].link, /^https:\/\/www\.prox-us\.com\/referral\.html\?code=PROX-P-/);
  await assert.rejects(inviteFor('owner', 'invite_request_0002'), /daily invite limit/);
  await account('alice');
  const results = await Promise.all([growth.acceptGrowthReferralForUid('alice', {code: issued[0].code, deviceId: 'alice-phone'}, '198.51.100.10'),
    growth.acceptGrowthReferralForUid('alice', {code: issued[0].code, deviceId: 'alice-phone'}, '198.51.100.10')]);
  assert.equal(results.filter(row => !row.replayed).length, 1);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 5);
  assert.equal((await db.doc('users/owner/meta/points').get()).exists, false);
  await conversation('alice');
  await growth.syncGrowthProgressForUid('alice');
  assert.equal((await db.doc('users/owner/meta/points').get()).exists, false, 'A conversation alone must not pay the mentor.');
  await completedMeetup('alice');
  await Promise.all([growth.syncGrowthProgressForUid('alice'), growth.syncGrowthProgressForUid('alice')]);
  assert.equal((await db.doc('users/owner/meta/points').get()).data().currentPoints, 10);
  assert.equal((await db.collection('users/owner/rewardClaims').get()).size, 1);
  assert.equal((await db.doc('growthReferrals/alice').get()).data().status, 'rewarded');
});

test('a single-use invite cannot be claimed by two accounts concurrently', async () => {
  const invite = await inviteFor();
  await account('alice'); await account('bob');
  const outcomes = await Promise.allSettled(['alice', 'bob'].map(uid => growth.acceptGrowthReferralForUid(uid, {code: invite.code, deviceId: uid}, `198.51.100.${uid.length}`)));
  assert.equal(outcomes.filter(row => row.status === 'fulfilled').length, 1);
  assert.equal((await db.collection('growthReferrals').get()).size, 1);
});

test('growth referral ancestry is preserved while both credits stay with the direct pair', async () => {
  await account('owner');
  await db.doc('users/owner').update({referrer: 'root', root_referrer: 'root'});
  const invite = await inviteFor();
  assert.equal((await db.doc(`referralCodes/${invite.code}`).get()).data().rootReferrerUid, 'root');
  await accept('alice', invite.code);
  assert.equal((await db.doc('users/alice').get()).data().referrer, 'owner');
  assert.equal((await db.doc('users/alice').get()).data().root_referrer, 'root');
  assert.equal((await db.doc('referralAttributions/alice').get()).data().rootReferrerUid, 'root');
  await conversation('alice');
  await completedMeetup('alice');
  await growth.syncGrowthProgressForUid('alice');
  await growth.syncGrowthProgressForUid('alice');
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 5);
  assert.equal((await db.doc('users/owner/meta/points').get()).data().currentPoints, 10);
  assert.equal((await db.doc('users/root/meta/points').get()).exists, false);
});

test('existing counters and one-sided chat cannot qualify activation; real reciprocal messages can', async () => {
  await account('alice', false);
  await db.doc('users/alice/meta/points').set({completedMeetups: 100});
  await db.doc('users/alice/stats/current').set({completedMeetups: 100});
  await db.doc('chats/forged_counter').set({participants: ['alice', 'peer'], messageCount: 999});
  await db.doc('chats/forged_counter/messages/one').set({from: 'alice', to: 'peer', text: 'One way', kind: 'text', ts: timestamp(Date.now())});
  await growth.syncGrowthProgressForUid('alice');
  assert.equal((await db.doc('growthProgress/alice').get()).data().qualifiedActivation, false);
  await db.doc('users/alice').set(completeProfile, {merge: true});
  await db.doc('chats/forged_counter/messages/two').set({from: 'peer', to: 'alice', text: 'system forged', kind: 'system', ts: timestamp(Date.now())});
  await growth.syncGrowthProgressForUid('alice');
  assert.equal((await db.doc('growthProgress/alice').get()).data().qualifiedActivation, false);
  await db.doc('chats/forged_counter/messages/three').set({from: 'peer', to: 'alice', text: 'Actual reply', kind: 'text', ts: timestamp(Date.now())});
  await growth.syncGrowthProgressForUid('alice');
  assert.equal((await db.doc('growthProgress/alice').get()).data().qualifiedActivation, true);
});

test('the tester mission counts post-approval chat and meetup evidence separately from lifetime activation', async () => {
  await account('alice'); await conversation('alice');
  await db.doc('users/alice/completedMeetups/old_receipt').set({completedAt: timestamp(Date.now() - DAY), recordedAt: timestamp(Date.now())});
  await growth.syncGrowthProgressForUid('alice'); await growth.joinTesterForUid('alice');
  await growth.reviewTesterForOperator('operator', {uid: 'alice', decision: 'approve'});
  let member = (await db.doc('growthMembers/alice').get()).data();
  assert.deepEqual(member.actions, {profile: true, chat: false, meetup: false});
  assert.equal(member.completed, false);
  await conversation('alice');
  await db.doc('users/alice/completedMeetups/new_receipt').set({completedAt: timestamp(Date.now()), recordedAt: timestamp(Date.now())});
  await growth.syncGrowthProgressForUid('alice');
  member = (await db.doc('growthMembers/alice').get()).data();
  assert.deepEqual(member.actions, {profile: true, chat: true, meetup: true});
  assert.equal(member.completedWithin48h, true);
});

test('duplicate inviter device holds both grants and the delay cannot be bypassed by review', async () => {
  const invite = await inviteFor('owner', 'duplicate_device_0001', 'shared-phone');
  const accepted = await accept('alice', invite.code, 'shared-phone', '198.51.100.10');
  assert.equal(accepted.welcomeStatus, 'held');
  assert.equal((await db.doc('users/alice/meta/points').get()).exists, false);
  await conversation('alice'); await growth.syncGrowthProgressForUid('alice');
  assert.equal((await db.doc('users/owner/meta/points').get()).exists, false);
  await completedMeetup('alice');
  await growth.syncGrowthProgressForUid('alice');
  await assert.rejects(growth.reviewGrowthRewardForUid('operator', {inviteeUid: 'alice', decision: 'release', note: 'Reviewed real tester'}), /delay/);
  await db.doc('growthReferrals/alice').update({holdUntil: timestamp(Date.now() - 1)});
  await growth.reviewGrowthRewardForUid('operator', {inviteeUid: 'alice', decision: 'release', note: 'Verified separate real users'});
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 5);
  assert.equal((await db.doc('users/owner/meta/points').get()).data().currentPoints, 10);
  assert.equal((await db.doc('growthReferrals/alice').get()).data().status, 'rewarded');
});

test('referrer monthly point caps hold later rewards without altering the welcome grant', async () => {
  await db.doc('growthOps/config').update({maxRewardPointsPerMonth: 10});
  for (const uid of ['alice', 'bob']) {
    const invite = await inviteFor('owner', `cap_invite_${uid}`);
    await accept(uid, invite.code, `phone-${uid}`, uid === 'alice' ? '198.51.100.10' : '198.51.100.11');
    await conversation(uid); await completedMeetup(uid); await growth.syncGrowthProgressForUid(uid);
  }
  assert.equal((await db.doc('users/owner/meta/points').get()).data().currentPoints, 10);
  assert.equal((await db.doc('growthReferrals/bob').get()).data().status, 'held');
  assert.deepEqual((await db.doc('growthReferrals/bob').get()).data().reasons, ['period_reward_cap']);
  assert.equal((await db.doc('users/bob/meta/points').get()).data().currentPoints, 5);
});

test('session retention works without diagnostics consent and opted-in fatal/error reports deduplicate', async () => {
  await account('alice');
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'private_session_0001', event: 'start', diagnosticsConsent: false});
  assert.equal((await growth.recordGrowthSessionForUid('alice', {sessionId: 'private_session_0001', event: 'error', source: 'map.load', requestId: 'error_private_0001', fatal: true, diagnosticsConsent: false})).recorded, false);
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'private_session_0001', event: 'end', diagnosticsConsent: false});
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'diagnostic_session_0001', event: 'start', diagnosticsConsent: true, metadata: {version: '0.20.0', build: '27', platform: 'android'}});
  const error = {sessionId: 'diagnostic_session_0001', event: 'error', source: 'map.load', requestId: 'error_duplicate_0001', fatal: true, diagnosticsConsent: true};
  await Promise.all([growth.recordGrowthSessionForUid('alice', error), growth.recordGrowthSessionForUid('alice', error)]);
  const today = (await growth.computeGrowthMetrics(1))[0];
  assert.equal(today.coverage.sessions, 2); assert.equal(today.coverage.optedInSessions, 1);
  assert.equal(today.crashFreeSessions, 0); assert.deepEqual(today.topErrors, [{source: 'map.load', count: 1}]);
  assert.equal((await db.collection('growthActivity').get()).size, 1);
  await assert.rejects(growth.recordGrowthSessionForUid('alice', {...error, requestId: 'error_badtext_0001', source: 'secret payload with email@example.test'}), /operation name/);
});

test('mature retention and activation use eligible cohorts and unknown crash coverage stays null', async () => {
  const now = Date.parse('2026-10-05T18:00:00Z'), created = Date.parse('2026-09-27T12:00:00Z');
  await account('alice', true, created); await account('newbie', true, now - 3600000);
  await db.doc('growthProgress/alice').update({qualifiedActivation: true, activatedAt: timestamp(created + 3600000)});
  for (const date of ['2026-09-28', '2026-10-04']) await db.doc(`growthActivity/${hash(['alice', date])}`).set({uid: 'alice', day: date, activeAt: timestamp(Date.parse(`${date}T12:00:00Z`))});
  const rows = await growth.computeGrowthMetrics(10, now);
  const cohort = rows.find(row => row.day === '2026-09-27'), today = rows.find(row => row.day === '2026-10-05');
  assert.equal(cohort.activationRate, 1); assert.equal(cohort.day1Retention, 1); assert.equal(cohort.day7Retention, 1);
  assert.equal(today.activationRate, null); assert.equal(today.day1Retention, null); assert.equal(today.crashFreeSessions, null);
});

test('support retries preserve one ticket across upgraded metadata, with private attachment validation', async () => {
  const ticketId = 'support_retry_0001', file = `supportAttachments/alice/${ticketId}/screenshot.png`;
  await admin.storage().bucket().file(file).save('image-fixture', {contentType: 'image/png'});
  const payload = {requestId: ticketId, expectedUid: 'alice', subject: 'Map jumps', message: 'Map jump', category: 'bug', source: 'settings',
    metadata: {version: '0.20.0', build: 27, platform: 'android', device: 'Pixel'}, attachmentPaths: [file]};
  const outcomes = await Promise.all([growth.submitGrowthSupportForUid('alice', payload), growth.submitGrowthSupportForUid('alice', payload)]);
  assert.equal(outcomes.filter(row => !row.replayed).length, 1);
  assert.equal((await growth.submitGrowthSupportForUid('alice', {...payload, source: 'reopened_draft', metadata: {version: '0.20.1'}})).replayed, true);
  assert.equal((await db.collection('supportTickets').get()).size, 1);
  assert.equal((await db.doc(`supportTickets/${ticketId}`).get()).data().firstResponseAt, undefined);
  await assert.rejects(growth.submitGrowthSupportForUid('bob', payload), /account changed/);
  await assert.rejects(growth.submitGrowthSupportForUid('alice', {...payload, requestId: 'support_wrong_0001', attachmentPaths: ['supportAttachments/bob/support_wrong_0001/private.png']}), /belong/);
  await assert.rejects(growth.submitGrowthSupportForUid('alice', {...payload, message: 'Changed payload'}), /already been used/);
});

test('only admins can triage, bugs need fixed-build details and first response means a real reply', async () => {
  const ticketId = 'support_triage_0001';
  await growth.submitGrowthSupportForUid('alice', {requestId: ticketId, subject: 'Crash', message: 'App closes', category: 'bug'});
  await assert.rejects(growth.getGrowthOps.run({auth: {uid: 'alice', token: {}}, data: {}}), /administrator/);
  await assert.rejects(growth.updateSupportTicket.run({auth: {uid: 'alice', token: {}}, data: {ticketId, requestId: 'triage_forged_0001', status: 'resolved'}}), /administrator/);
  await growth.updateSupportForOperator('operator', {ticketId, requestId: 'triage_classify_0001', status: 'acknowledged', severity: 'P0'});
  assert.equal((await db.doc(`supportTickets/${ticketId}`).get()).data().firstResponseAt, undefined);
  await assert.rejects(growth.updateSupportForOperator('operator', {ticketId, requestId: 'triage_bad_fix_0001', status: 'resolved'}), /version and build/);
  const fix = {ticketId, requestId: 'triage_fixed_0001', status: 'resolved', fixedVersion: '0.20.1', fixedBuild: '28'};
  await growth.updateSupportTicket.run({auth: {uid: 'operator', token: {admin: true}}, data: fix});
  assert.equal((await growth.updateSupportForOperator('operator', fix)).replayed, true);
  const ticket = (await db.doc(`supportTickets/${ticketId}`).get()).data();
  assert.ok(ticket.firstResponseAt); assert.match(ticket.lastReply, /0\.20\.1, build 28/);
  assert.equal((await db.collection(`supportTickets/${ticketId}/replies`).get()).size, 1);
  await assert.rejects(growth.replyToSupportForUid('mallory', {ticketId, requestId: 'reply_forged_0001', message: 'Forged'}), /reporter/);
  await growth.replyToSupportForUid('alice', {ticketId, requestId: 'reply_actual_0001', message: 'Thanks, fixed'});
});

test('canonical quick feedback preserves the existing two-point daily reward and cross-account requests fail closed', async () => {
  await account('alice');
  const payload = {requestId: 'support_feedback_reward_0001', expectedUid: 'alice', subject: 'UX detail',
    message: 'The nearby screen jumped while I was scrolling the list.', category: 'ux', source: 'settings_support_feedback'};
  const first = await growth.submitGrowthSupportForUid('alice', payload);
  assert.equal(first.reward.awarded, true); assert.equal(first.reward.points, 2);
  const retry = await growth.submitGrowthSupportForUid('alice', payload);
  assert.equal(retry.reward.alreadyClaimed, true);
  const second = await growth.submitGrowthSupportForUid('alice', {...payload, requestId: 'support_feedback_reward_0002'});
  assert.equal(second.reward.dailyLimitReached, true);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 2);
  await db.doc('growthOps/config').update({enabled: false});
  assert.equal((await growth.submitGrowthSupportForUid('alice', {...payload, requestId: 'support_while_paused_0001'})).submitted, true);
  await assert.rejects(growth.getGrowthStatus.run({auth: {uid: 'bob', token: {}}, data: {expectedUid: 'alice'}}), /account changed/);
  await assert.rejects(growth.updateGrowthConfig.run({auth: {uid: 'operator', token: {admin: true}}, data: {expectedUid: 'someone-else', config: {enabled: true}}}), /account changed/);
});

test('a deleted administrator cannot release held rewards or read the ops dashboard', async () => {
  const invite = await inviteFor('owner', 'deleted_admin_invite', 'shared-phone');
  await accept('alice', invite.code, 'shared-phone');
  await db.doc('growthReferrals/alice').update({holdUntil: timestamp(Date.now() - 1)});
  await db.doc('accountDeletions/operator').set({status: 'processing'});
  await assert.rejects(growth.reviewGrowthReward.run({auth: {uid: 'operator', token: {admin: true}}, data: {inviteeUid: 'alice', decision: 'release', note: 'Try cached token'}}), /unavailable/);
  await assert.rejects(growth.getGrowthOps.run({auth: {uid: 'operator', token: {admin: true}}, data: {}}), /being deleted/);
  assert.equal((await db.doc('users/alice/meta/points').get()).exists, false);
});

test('older canonical tickets follow immutable owner aliases for replies and triage', async () => {
  await db.doc('supportTickets/legacy_owner_ticket').set({ownerUid: 'alice', subject: 'Earlier question', message: 'Help', status: 'open', createdAt: timestamp(Date.now())});
  await growth.replyToSupportForUid('alice', {ticketId: 'legacy_owner_ticket', requestId: 'legacy_owner_reply', message: 'Additional detail'});
  await growth.updateSupportForOperator('operator', {ticketId: 'legacy_owner_ticket', requestId: 'legacy_owner_triage', reply: 'We are reviewing this.', status: 'in_progress'});
  assert.equal((await db.doc('supportTickets/legacy_owner_ticket').get()).data().lastReply, 'We are reviewing this.');
  await db.doc('supportTickets/conflicting_alias_ticket').set({ownerUid: 'alice', uid: 'bob', subject: 'Old conflicting alias', status: 'open', createdAt: timestamp(Date.now())});
  await assert.rejects(growth.replyToSupportForUid('bob', {ticketId: 'conflicting_alias_ticket', requestId: 'conflicting_alias_reply', message: 'Cannot claim this'}), /reporter/);
  await growth.replyToSupportForUid('alice', {ticketId: 'conflicting_alias_ticket', requestId: 'actual_alias_owner_reply', message: 'Actual owner'});
});

test('imported detailed feedback shares its original financial receipt and cannot re-credit on a later day', async () => {
  await account('alice');
  await db.doc('feedback/original_feedback_0001').set({uid: 'alice', text: 'Detailed original feedback about the nearby screen.', source: 'settings_support_feedback'});
  await claimReward('alice', 'feedback', 'original_feedback_0001');
  await syncLegacySupport('feedback', 'original_feedback_0001');
  await db.doc(`users/alice/rewardLimits/${new Date().toISOString().slice(0, 10)}`).delete();
  const canonical = legacySupportTicketId('feedback', 'original_feedback_0001');
  const result = await claimReward('alice', 'feedback', canonical);
  assert.equal(result.alreadyClaimed, true);
  assert.equal((await db.doc('users/alice/meta/points').get()).data().currentPoints, 2);
  assert.equal((await db.collection('users/alice/rewardClaims').get()).size, 1);
  await db.doc('feedback/deleted_original_0001').set({uid: 'alice', text: 'Detailed feedback that will be removed from the source.', source: 'settings_support_feedback'});
  await syncLegacySupport('feedback', 'deleted_original_0001');
  await db.doc('feedback/deleted_original_0001').delete();
  await assert.rejects(claimReward('alice', 'feedback', legacySupportTicketId('feedback', 'deleted_original_0001')), /detailed feedback/);
});

test('rules keep growth outcomes server-only and support attachments/replies private', async () => {
  const ticketId = 'support_rules_0001';
  await growth.submitGrowthSupportForUid('alice', {requestId: ticketId, subject: 'Question', message: 'Help?', category: 'question'});
  await growth.replyToSupportForUid('alice', {ticketId, requestId: 'reply_rules_0001', message: 'Details'});
  const alice = env.authenticatedContext('alice'), bob = env.authenticatedContext('bob'), op = env.authenticatedContext('operator', {admin: true});
  await assertSucceeds(getDoc(doc(alice.firestore(), `supportTickets/${ticketId}`)));
  await assertFails(getDoc(doc(bob.firestore(), `supportTickets/${ticketId}`)));
  await assertSucceeds(getDocs(query(collection(alice.firestore(), `supportTickets/${ticketId}/replies`), orderBy('createdAt'))));
  await assertFails(getDocs(collection(bob.firestore(), `supportTickets/${ticketId}/replies`)));
  await assertFails(updateDoc(doc(alice.firestore(), `supportTickets/${ticketId}`), {firstResponseAt: new Date(), status: 'resolved'}));
  await assertFails(updateDoc(doc(op.firestore(), `supportTickets/${ticketId}`), {status: 'resolved'}));
  for (const collectionName of ['growthProgress', 'growthReferrals', 'growthSessions', 'growthOps', 'growthIdentitySignals']) await assertFails(setDoc(doc(alice.firestore(), `${collectionName}/alice`), {qualifiedActivation: true}));
  await assertFails(setDoc(doc(alice.firestore(), 'referralCodes/PROX-FORGED'), {referrerUid: 'alice', source: 'growth'}));
  await assertFails(setDoc(doc(alice.firestore(), 'supportTickets/forged'), {uid: 'alice', status: 'open', firstResponseAt: new Date()}));
  await assertFails(setDoc(doc(alice.firestore(), 'feedback/forged_owner'), {ownerUid: 'alice', uid: 'bob', text: 'Mixed owner aliases'}));
  await assertSucceeds(setDoc(doc(alice.firestore(), 'feedback/immutable_owner'), {uid: 'alice', text: 'Original text'}));
  await assertFails(updateDoc(doc(alice.firestore(), 'feedback/immutable_owner'), {uid: 'bob'}));
  const filePath = `supportAttachments/alice/${ticketId}/screen.png`;
  await assertSucceeds(uploadBytes(ref(alice.storage(), filePath), Buffer.from('fixture'), {contentType: 'image/png'}));
  await assertSucceeds(uploadBytes(ref(alice.storage(), filePath), Buffer.from('retry'), {contentType: 'image/png'}));
  await assertSucceeds(getBytes(ref(alice.storage(), filePath)));
  await assertSucceeds(getBytes(ref(op.storage(), filePath)));
  await assertFails(getBytes(ref(bob.storage(), filePath)));
  await assertFails(uploadBytes(ref(bob.storage(), filePath), Buffer.from('forged'), {contentType: 'image/png'}));
  await assertFails(uploadBytes(ref(alice.storage(), `supportAttachments/alice/${ticketId}/payload.txt`), Buffer.from('fixture'), {contentType: 'text/plain'}));
});

test('account deletion removes growth membership, identities, private reports, events and screenshots', async () => {
  await account('alice'); await growth.joinTesterForUid('alice'); await growth.reviewTesterForOperator('operator', {uid: 'alice', decision: 'approve'});
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'session_erasure_0001', event: 'start'});
  await db.doc('growthIdentitySignals/device_fake').set({uids: ['alice', 'bob']});
  await growth.submitGrowthSupportForUid('alice', {requestId: 'support_erasure_0001', subject: 'Private', message: 'Remove me', category: 'question'});
  await admin.storage().bucket().file('supportAttachments/alice/support_erasure_0001/screen.png').save('fixture', {contentType: 'image/png'});
  await eraseUserData('alice');
  for (const collectionName of ['growthProgress', 'growthMembers', 'growthTesterApplications']) assert.equal((await db.doc(`${collectionName}/alice`).get()).exists, false);
  assert.equal((await db.collection('growthSessions').get()).size, 0);
  assert.equal((await db.collection('growthSessionEvents').get()).size, 0);
  assert.equal((await db.doc('supportTickets/support_erasure_0001').get()).exists, false);
  assert.deepEqual((await db.doc('growthIdentitySignals/device_fake').get()).data().uids, ['bob']);
  assert.deepEqual((await db.doc('growthOps/cohort').get()).data().members, []);
  assert.equal((await admin.storage().bucket().file('supportAttachments/alice/support_erasure_0001/screen.png').exists())[0], false);
  await assert.rejects(growth.ensureGrowthIdentity('alice', Date.now()), /being deleted/);
});

test('a remote legacy token retry preserves prior progress and eligibility without consuming the token', async () => {
  await account('alice'); await account('owner');
  await db.doc('users/alice').update({referrer: 'owner'});
  await db.doc('users/owner/referrals/alice').set({uid: 'alice', meetupsCompleted: 5, inPersonVerified: true, rewardEligible: true, rewardGranted: true, joinedAt: timestamp(Date.now() - DAY)});
  const token = 'T-123456789012345678';
  await db.doc(`referralSingleUseTokens/${token}`).set({referrerUid: 'owner', status: 'new', expiresAt: timestamp(Date.now() + 60000)});
  const auth = admin.auth(), previous = auth.verifyIdToken;
  auth.verifyIdToken = async () => ({uid: 'alice'});
  try {
    const response = httpResponse();
    await finalizeReferralSingleUseToken({method: 'POST', body: {token}, get: name => name.toLowerCase() === 'authorization' ? 'Bearer fake' : ''}, response);
    assert.equal(response.statusCode, 409);
    assert.equal(response.body.error, 'in_person_verification_required');
    const referral = (await db.doc('users/owner/referrals/alice').get()).data();
    assert.equal(referral.meetupsCompleted, 5); assert.equal(referral.inPersonVerified, true); assert.equal(referral.rewardGranted, true);
    assert.equal((await db.doc(`referralSingleUseTokens/${token}`).get()).data().status, 'new');
  } finally {auth.verifyIdToken = previous;}
});

test('referral downloads honor an explicit iOS target even from a desktop browser', async () => {
  await db.doc('referralCodes/PROX-PLATFORM').set({referrerUid: 'owner', active: true});
  const previous = process.env.PROX_REFERRAL_IOS_URL;
  process.env.PROX_REFERRAL_IOS_URL = 'https://testflight.apple.com/join/tester';
  try {
    const response = httpResponse();
    await referralApkDownload({method: 'HEAD', query: {code: 'PROX-PLATFORM', platform: 'ios'}, get: () => 'desktop'}, response);
    assert.match(response.url, /^https:\/\/testflight\.apple\.com\//);
  } finally {if (previous === undefined) delete process.env.PROX_REFERRAL_IOS_URL; else process.env.PROX_REFERRAL_IOS_URL = previous;}
});

test('delayed progress processing uses server evidence times for 24-hour activation and 48-hour missions', async () => {
  const before = Date.now();
  await account('alice', true, before - 3600000);
  await growth.syncGrowthProgressForUid('alice');
  await growth.joinTesterForUid('alice');
  await growth.reviewTesterForOperator('operator', {uid: 'alice', decision: 'approve'});
  await conversation('alice');
  await db.doc('users/alice/completedMeetups/actual_completion').set({completedAt: timestamp(Date.now()), recordedAt: timestamp(Date.now())});
  const lastMessage = (await db.collection('chats/alice_peer/messages').get()).docs.reduce((latest, row) => Math.max(latest, row.createTime.toMillis()), 0);
  const actualNow = Date.now;
  try {
    Date.now = () => actualNow() + 3 * DAY;
    await growth.syncGrowthProgressForUid('alice');
    const progress = (await db.doc('growthProgress/alice').get()).data();
    const member = (await db.doc('growthMembers/alice').get()).data();
    assert.equal(progress.activatedAt.toMillis(), lastMessage);
    assert.equal(member.completedWithin48h, true);
    assert.ok(member.completedAt.toMillis() < before + 60000);
    const rows = await growth.computeGrowthMetrics(4);
    const row = rows.find(item => item.day === new Date(before - 3600000).toISOString().slice(0, 10));
    assert.equal(row.activatedWithin24h, 1);
    assert.equal(row.activationRate, 1);
    await db.doc('users/alice').update({displayName: 'Edited later'});
    await db.recursiveDelete(db.doc('chats/alice_peer'));
    await growth.syncGrowthProgressForUid('alice');
    assert.equal((await db.doc('growthProgress/alice').get()).data().activatedAt.toMillis(), lastMessage);
    assert.equal((await db.doc('growthMembers/alice').get()).data().completedAt.toMillis(), member.completedAt.toMillis());
  } finally {Date.now = actualNow;}
});

test('growth invite downloads require a configured pilot build and preserve legacy build routing', async () => {
  const invite = await inviteFor();
  const keys = ['PROX_GROWTH_ANDROID_URL', 'PROX_GROWTH_IOS_URL', 'PROX_REFERRAL_ANDROID_URL'];
  const prior = Object.fromEntries(keys.map(key => [key, process.env[key]]));
  try {
    delete process.env.PROX_GROWTH_ANDROID_URL;
    delete process.env.PROX_GROWTH_IOS_URL;
    process.env.PROX_REFERRAL_ANDROID_URL = 'https://github.com/marolam/prox/releases/latest/download/app-release.apk';
    const request = query => ({method: 'HEAD', query, get: () => 'desktop'});
    const missing = httpResponse();
    await referralApkDownload(request({code: invite.code}), missing);
    assert.equal(missing.statusCode, 503);
    assert.equal(missing.body.error, 'growth_android_build_unavailable');
    const pilot = 'https://github.com/marolam/prox/releases/download/v0.20.0%2B27-staging/app-release-staging.apk';
    process.env.PROX_GROWTH_ANDROID_URL = pilot;
    const selected = httpResponse();
    await referralApkDownload(request({code: invite.code}), selected);
    assert.equal(selected.url, pilot);
    const ios = httpResponse();
    await referralApkDownload(request({code: invite.code, platform: 'ios'}), ios);
    assert.equal(ios.body.error, 'growth_ios_invitation_required');
    process.env.PROX_GROWTH_ANDROID_URL = 'https://evil.example.test/app.apk';
    const unsafe = httpResponse();
    await referralApkDownload(request({code: invite.code, apk: pilot}), unsafe);
    assert.equal(unsafe.statusCode, 503);
    await db.doc('referralCodes/PROX-LEGACY').set({referrerUid: 'owner', active: true});
    const legacy = httpResponse();
    await referralApkDownload(request({code: 'PROX-LEGACY'}), legacy);
    assert.equal(legacy.url, process.env.PROX_REFERRAL_ANDROID_URL);
    process.env.PROX_GROWTH_IOS_URL = 'https://testflight.apple.com/join/actualPilot';
    const iosSelected = httpResponse();
    await referralApkDownload(request({code: invite.code, platform: 'ios'}), iosSelected);
    assert.equal(iosSelected.url, process.env.PROX_GROWTH_IOS_URL);
  } finally {
    for (const key of keys) if (prior[key] === undefined) delete process.env[key]; else process.env[key] = prior[key];
  }
});

test('reported fatal sessions count in crash-free coverage even when no end event arrives', async () => {
  await account('alice');
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'fatal_without_end_0001', event: 'start', diagnosticsConsent: true});
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'fatal_without_end_0001', event: 'error', requestId: 'fatal_request_0001', source: 'app.runtime', fatal: true, diagnosticsConsent: true});
  let row = (await growth.computeGrowthMetrics(1))[0];
  assert.equal(row.crashFreeSessions, 0);
  // Current collection closes a fatal session even without a client end event.
  assert.equal(row.coverage.completedDiagnosticSessions, 1);
  const fatalSession = (await db.collection('growthSessions').where('sessionId', '==', 'fatal_without_end_0001').get()).docs[0];
  // Defensive coverage for older/inconsistent stored rows without that flag.
  await fatalSession.ref.update({ended: false});
  row = (await growth.computeGrowthMetrics(1))[0];
  assert.equal(row.crashFreeSessions, 0);
  assert.equal(row.coverage.completedDiagnosticSessions, 0);
  assert.equal(row.coverage.observedDiagnosticSessions, 1);
  assert.equal(row.coverage.reportedFatalSessions, 1);
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'healthy_completed_0001', event: 'start', diagnosticsConsent: true});
  await growth.recordGrowthSessionForUid('alice', {sessionId: 'healthy_completed_0001', event: 'end', diagnosticsConsent: true});
  row = (await growth.computeGrowthMetrics(1))[0];
  assert.equal(row.crashFreeSessions, 0.5);
  assert.equal(row.coverage.completedDiagnosticSessions, 1);
  assert.equal(row.coverage.observedDiagnosticSessions, 2);
});
