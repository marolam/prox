const {before, after, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, getDocs, collection, collectionGroup, query, where, and, or, orderBy, limit} = require('firebase/firestore');
const {ref, uploadBytes, getMetadata} = require('firebase/storage');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-prox-audit', firestore: {
    host: '127.0.0.1', port: 8088,
    rules: readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
  }, storage: {host: '127.0.0.1', port: 9198, rules: readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });
const db = uid => env.authenticatedContext(uid).firestore();

test('closed chats reject new messages and cannot be reopened by participants', async () => {
  await seed({'chats/ended': {participants: ['alice', 'bob'], closedAt: new Date(), chatGate: {status: 'expired'}}});
  await assertFails(setDoc(doc(db('alice'), 'chats/ended/messages/new'), {from: 'alice', to: 'bob', text: 'Still here', read: false}));
  await assertFails(updateDoc(doc(db('bob'), 'chats/ended'), {closedAt: null}));
  await assertFails(updateDoc(doc(db('bob'), 'chats/ended'), {'chatGate.status': 'accepted'}));
});

test('meetups cannot move backward, change a confirmed pin, forge an outcome, or be deleted while active', async () => {
  await seed({'meetups/safe': {aUid: 'alice', bUid: 'bob', status: 'live', locationStatus: 'confirmed', lat: 10, lng: 10}});
  const ref = doc(db('alice'), 'meetups/safe');
  await assertFails(updateDoc(ref, {status: 'accepted'}));
  await assertFails(updateDoc(ref, {lat: 11}));
  await assertFails(updateDoc(ref, {locationStatus: 'proposed'}));
  await assertFails(updateDoc(ref, {outcome: 'completed'}));
  await assertFails(deleteDoc(ref));
  await assertSucceeds(updateDoc(ref, {aArrived: true}));
  await assertFails(updateDoc(ref, {aArrived: false}));
  await seed({'meetups/safe': {aUid: 'alice', bUid: 'bob', status: 'cancelled', aArrived: true, bArrived: true}});
  await assertFails(updateDoc(ref, {status: 'completed'}));
  await assertFails(setDoc(doc(db('alice'), 'meetups/safe/beacon/live'), {lat: 10}));
  await assertFails(setDoc(doc(db('alice'), 'users/alice/meetupOutcomes/forged'), {outcome: 'completed'}));
  await assertFails(getDoc(doc(db('bob'), 'users/alice/meetupOutcomes/forged')));
});
async function seed(entries) {
  await env.withSecurityRulesDisabled(async context => {
    for (const [name, data] of Object.entries(entries)) await setDoc(doc(context.firestore(), name), data);
  });
}

test('private support and reports cannot be claimed by another user or self-resolved', async () => {
  await seed({'support_tickets/ticket': {uid: 'alice', status: 'open'}, 'bugReports/report': {ownerUid: 'alice', status: 'open', title: 'Issue'}});
  await assertFails(updateDoc(doc(db('mallory'), 'support_tickets/ticket'), {technicianId: 'mallory'}));
  await assertFails(getDoc(doc(db('mallory'), 'support_tickets/ticket')));
  await assertFails(updateDoc(doc(db('alice'), 'support_tickets/ticket'), {payoutGranted: true}));
  await assertFails(updateDoc(doc(db('alice'), 'bugReports/report'), {status: 'resolved'}));
  await assertSucceeds(updateDoc(doc(db('alice'), 'bugReports/report'), {description: 'More detail'}));
  await assertSucceeds(getDocs(query(collection(db('alice'), 'bugReports'), where('ownerUid', '==', 'alice'))));
  await assertSucceeds(setDoc(doc(db('alice'), 'supportTickets/new'), {uid: 'alice', subject: 'Help', status: 'open'}));
  await assertFails(setDoc(doc(db('alice'), 'support_tickets/forged'), {uid: 'alice', status: 3, payoutGranted: true, technicianId: 'alice'}));
});

test('entitlements, balances, stats and purchase receipts are server-authoritative', async () => {
  for (const name of ['billing/entitlements', 'billing/invoices/items/fake', 'meta/points', 'meta/progression', 'stats/trust', 'store/purchases/items/fake']) {
    await assertFails(setDoc(doc(db('alice'), `users/alice/${name}`), {currentPoints: 999999, businessPurchased: true}));
  }
  await seed({'users/alice/billing/entitlements': {businessPurchased: true}});
  await assertSucceeds(getDoc(doc(db('alice'), 'users/alice/billing/entitlements')));
  await assertFails(getDoc(doc(db('mallory'), 'users/alice/billing/entitlements')));
});

test('chat transactions can preflight missing documents and real send/read receipts work', async () => {
  await assertSucceeds(getDoc(doc(db('alice'), 'chats/alice__bob')));
  await assertSucceeds(setDoc(doc(db('alice'), 'chats/alice__bob'), {participants: ['alice', 'bob'], isGroup: false}));
  await assertSucceeds(setDoc(doc(db('alice'), 'chats/alice__bob/messages/hello'), {from: 'alice', to: 'bob', text: 'Hello', kind: 'text', read: false}));
  await assertSucceeds(updateDoc(doc(db('bob'), 'chats/alice__bob/messages/hello'), {read: true}));
  await assertSucceeds(getDocs(query(collection(db('alice'), 'chats'), where('participants', 'array-contains', 'alice'))));
});

test('chat participants cannot forge senders, alter old messages or add outsiders', async () => {
  await seed({'chats/pair': {participants: ['alice', 'bob'], isGroup: false}, 'chats/pair/messages/m': {from: 'alice', to: 'bob', text: 'Original', read: false}});
  await assertFails(setDoc(doc(db('bob'), 'chats/pair/messages/fake'), {from: 'alice', to: 'bob', text: 'Forged'}));
  await assertFails(updateDoc(doc(db('bob'), 'chats/pair/messages/m'), {text: 'Edited'}));
  await assertFails(updateDoc(doc(db('bob'), 'chats/pair'), {participants: ['alice', 'bob', 'mallory']}));
  await assertFails(updateDoc(doc(db('bob'), 'chats/pair'), {moderatorUid: 'bob'}));
  await assertFails(deleteDoc(doc(db('bob'), 'chats/pair/messages/m')));
  await assertFails(getDoc(doc(db('mallory'), 'chats/pair/messages/m')));
});

test('only an existing group moderator can change membership', async () => {
  await seed({'chats/group': {participants: ['alice', 'bob'], isGroup: true, moderatorUid: 'alice'}});
  await assertSucceeds(updateDoc(doc(db('alice'), 'chats/group'), {participants: ['alice', 'bob', 'carol']}));
  await assertFails(updateDoc(doc(db('bob'), 'chats/group'), {participants: ['alice', 'bob', 'carol', 'mallory']}));
});

test('durable blocks prevent messages, new direct chats and meetup requests in both directions', async () => {
  await seed({'chats/pair': {participants: ['alice', 'bob']}});
  await assertSucceeds(setDoc(doc(db('bob'), 'users/bob/blocks/alice'), {uid: 'alice'}));
  for (const [sender, recipient] of [['alice', 'bob'], ['bob', 'alice']]) {
    await assertFails(setDoc(doc(db(sender), `chats/pair/messages/${sender}`), {from: sender, to: recipient, text: 'Blocked'}));
    await assertFails(setDoc(doc(db(sender), `meetups/${sender}`), {aUid: sender, bUid: recipient, status: 'requested'}));
  }
  await assertFails(setDoc(doc(db('alice'), 'chats/new'), {participants: ['alice', 'bob']}));
  await assertSucceeds(deleteDoc(doc(db('bob'), 'users/bob/blocks/alice')));
  await assertSucceeds(setDoc(doc(db('alice'), 'chats/pair/messages/allowed'), {from: 'alice', to: 'bob', text: 'Unblocked'}));
});

test('meetup legacy updates work but participant and status-event impersonation fail', async () => {
  await assertSucceeds(getDoc(doc(db('alice'), 'meetups/pair')));
  await assertSucceeds(setDoc(doc(db('alice'), 'meetups/pair'), {aUid: 'alice', bUid: 'bob', status: 'live'}));
  await assertSucceeds(updateDoc(doc(db('alice'), 'meetups/pair'), {locationLabel: 'Library'}));
  await assertFails(updateDoc(doc(db('alice'), 'meetups/pair'), {bUid: 'mallory'}));
  await assertFails(updateDoc(doc(db('alice'), 'meetups/pair'), {lastStatusEvent: {id: 'x', actorUid: 'bob', type: 'arrived'}}));
  await assertFails(getDoc(doc(db('mallory'), 'meetups/pair')));
});

test('threads and debug push are private, and deletion markers revoke stale-token access', async () => {
  await seed({'threads/private': {participants: ['alice', 'bob']}, 'accountDeletions/alice': {status: 'processing'}});
  await assertFails(getDoc(doc(db('mallory'), 'threads/private')));
  await assertFails(setDoc(doc(db('bob'), 'devPush/attack'), {uid: 'alice', text: 'Spam'}));
  await assertFails(setDoc(doc(db('alice'), 'users/alice/settings/x'), {enabled: true}));
});

test('trust receipts require a completed meetup with the actual peer', async () => {
  await seed({'meetups/m': {aUid: 'alice', bUid: 'bob', status: 'completed'}});
  await assertSucceeds(setDoc(doc(db('alice'), 'users/alice/trustFeedback/m'), {meetupId: 'm', otherUid: 'bob', wouldMeetAgain: true}));
  await assertFails(setDoc(doc(db('alice'), 'users/alice/trustFeedback/m'), {meetupId: 'm', otherUid: 'mallory', wouldMeetAgain: true}));
  await assertFails(setDoc(doc(db('mallory'), 'users/mallory/trustFeedback/m'), {meetupId: 'm', otherUid: 'bob', wouldMeetAgain: true}));
});

test('rating entries work without a parent shell and only the rater can edit them', async () => {
  await seed({'meetups/m': {aUid: 'alice', bUid: 'bob', status: 'completed'}});
  await assertSucceeds(setDoc(doc(db('alice'), 'ratings/m/entries/alice'), {thumb: true, reason: null}));
  await assertSucceeds(getDoc(doc(db('alice'), 'ratings/m/entries/alice')));
  await assertFails(setDoc(doc(db('bob'), 'ratings/m/entries/alice'), {thumb: false}));
});

test('meetup participants cannot fake peer arrival or rewrite completed cycle receipts', async () => {
  await seed({'meetups/m': {aUid: 'alice', bUid: 'bob', status: 'live', aArrived: false, bArrived: false}});
  await assertFails(updateDoc(doc(db('alice'), 'meetups/m'), {aArrived: true, bArrived: true, status: 'completed'}));
  await assertSucceeds(updateDoc(doc(db('alice'), 'meetups/m'), {aArrived: true}));
  await assertSucceeds(updateDoc(doc(db('bob'), 'meetups/m'), {bArrived: true, status: 'completed', completedAt: new Date()}));
  await assertFails(updateDoc(doc(db('alice'), 'meetups/m'), {completedAt: new Date(Date.now() + 60000)}));
  await assertFails(setDoc(doc(db('alice'), 'meetups/fake'), {aUid: 'alice', bUid: 'bob', status: 'completed', aArrived: true, bArrived: true}));
});

test('public discovery is a read-only projection while account details, policy and stats stay private', async () => {
  await seed({'users/alice': {email: 'private@example.test', referrer: 'bob'}, 'profiles/alice': {keywordWorkspace: {private: ['private']}}, 'publicProfiles/alice': {displayName: 'Alice'}, 'users/alice/meta/policyAcks': {versions: {}}, 'users/alice/stats/current': {count: 1}, 'users/alice/stats/trust': {total: 4, positive: 3}});
  await assertSucceeds(getDoc(doc(db('alice'), 'users/alice')));
  for (const name of ['users/alice', 'profiles/alice', 'users/alice/meta/policyAcks', 'users/alice/stats/current']) await assertFails(getDoc(doc(db('bob'), name)));
  await assertSucceeds(getDoc(doc(db('bob'), 'publicProfiles/alice')));
  await assertSucceeds(getDoc(doc(db('bob'), 'users/alice/stats/trust')));
  await assertFails(setDoc(doc(db('alice'), 'publicProfiles/alice'), {email: 'leaked'}));
  await assertFails(updateDoc(doc(db('alice'), 'users/alice'), {referrer: 'carol'}));
  await assertFails(deleteDoc(doc(db('alice'), 'users/alice')));
});

test('referral code owners are immutable and meetup counts and mutual-party flags are server owned', async () => {
  await assertSucceeds(setDoc(doc(db('alice'), 'referralCodes/PROX-ABC'), {referrerUid: 'alice', rootReferrerUid: 'alice', active: true, remaining: 5}));
  await assertFails(updateDoc(doc(db('alice'), 'referralCodes/PROX-ABC'), {referrerUid: 'bob'}));
  await assertFails(setDoc(doc(db('alice'), 'referralCodes/PROX-FORGED'), {referrerUid: 'bob', ownerUid: 'alice'}));
  await assertSucceeds(setDoc(doc(db('alice'), 'users/alice/party/bob'), {uid: 'bob', mutual: false}));
  await assertFails(updateDoc(doc(db('alice'), 'users/alice/party/bob'), {mutual: true}));
  await seed({'users/alice/referrals/bob': {uid: 'bob', meetupsCompleted: 1, inPersonVerified: true}});
  await assertFails(updateDoc(doc(db('alice'), 'users/alice/referrals/bob'), {meetupsCompleted: 4}));
});

test('Storage enforces media ownership, image types and deletion-marker revocation', async () => {
  const alice = env.authenticatedContext('alice').storage();
  const bob = env.authenticatedContext('bob').storage();
  await assertSucceeds(uploadBytes(ref(alice, 'profiles/alice/a.png'), new Uint8Array([1, 2]), {contentType: 'image/png'}));
  await assertSucceeds(getMetadata(ref(bob, 'profiles/alice/a.png')));
  await assertFails(uploadBytes(ref(bob, 'profiles/alice/a.png'), new Uint8Array([3]), {contentType: 'image/png'}));
  await assertFails(uploadBytes(ref(alice, 'profiles/alice/script.svg'), new Uint8Array([3]), {contentType: 'image/svg+xml'}));
  await seed({'accountDeletions/alice': {status: 'processing'}});
  await assertFails(uploadBytes(ref(alice, 'profiles/alice/new.png'), new Uint8Array([3]), {contentType: 'image/png'}));
});

test('discovery filters multiple coordinate ranges and antimeridian intervals before result limits', async () => {
  await seed({
    'users/east/presence/current': {kind: 'current', latitude: 12, longitude: 179.5},
    'users/west/presence/current': {kind: 'current', latitude: 12, longitude: -179.5},
    'users/distant/presence/current': {kind: 'current', latitude: 11, longitude: 0},
    'users/south/presence/current': {kind: 'current', latitude: 0, longitude: 179.5},
  });
  const result = await assertSucceeds(getDocs(query(collectionGroup(db('alice'), 'presence'),
    and(where('kind', '==', 'current'), where('latitude', '>=', 10), where('latitude', '<=', 15),
      or(and(where('longitude', '>=', 179), where('longitude', '<=', 180)), and(where('longitude', '>=', -180), where('longitude', '<=', -179)))),
    orderBy('latitude'), orderBy('longitude'), limit(2))));
  assert.deepEqual(result.docs.map(item => item.ref.parent.parent.id).sort(), ['east', 'west']);
});

test('payment reconciliation is admin-private and operator notes cannot forge financial resolution', async () => {
  await seed({'paymentReconciliation/refund': {uid: 'alice', status: 'review_required', reason: 'spent_points'}});
  await assertFails(getDoc(doc(db('alice'), 'paymentReconciliation/refund')));
  await assertFails(setDoc(doc(db('alice'), 'paymentReconciliation/fake'), {uid: 'alice', status: 'reconciled'}));
  const adminDb = env.authenticatedContext('operator', {admin: true}).firestore();
  await assertSucceeds(getDoc(doc(adminDb, 'paymentReconciliation/refund')));
  await assertSucceeds(updateDoc(doc(adminDb, 'paymentReconciliation/refund'), {operatorNote: 'Reviewing provider receipt', operatorStatus: 'investigating'}));
  await assertFails(updateDoc(doc(adminDb, 'paymentReconciliation/refund'), {status: 'reconciled'}));
});


test('Party consent is server-only and pending users cannot read Party profiles or private feedback', async () => {
  await seed({
    'partyConnections/pair': {members:['alice','bob'],status:'pending',decisions:{alice:'add'}},
    'users/alice/partyProfile/sharing': {sharePhone:true,phone:'555-0100'},
    'meetups/rating': {aUid:'alice',bUid:'bob',status:'completed'},
    'ratings/rating/entries/alice': {thumb:false,reason:'Private feedback'},
  });
  await assertSucceeds(getDocs(query(collection(db('alice'),'partyConnections'),where('members','array-contains','alice'))));
  await assertFails(getDoc(doc(db('mallory'),'partyConnections/pair')));
  await assertFails(updateDoc(doc(db('alice'),'partyConnections/pair'),{decisions:{alice:'add',bob:'add'},status:'connected'}));
  await assertFails(getDoc(doc(db('bob'),'users/alice/partyProfile/sharing')));
  await assertFails(getDoc(doc(db('bob'),'ratings/rating/entries/alice')));
  await assertSucceeds(getDoc(doc(db('alice'),'ratings/rating/entries/alice')));
  await seed({'users/alice/party/bob':{mutual:false},'users/bob/party/alice':{mutual:false}});
  await assertFails(getDoc(doc(db('bob'),'users/alice/partyProfile/sharing')));
  await seed({'users/alice/party/bob':{mutual:true},'users/bob/party/alice':{mutual:true}});
  await assertSucceeds(getDoc(doc(db('bob'),'users/alice/partyProfile/sharing')));
  await seed({'users/bob/blocks/alice':{uid:'alice'}});
  await assertFails(getDoc(doc(db('bob'),'users/alice/partyProfile/sharing')));
});
