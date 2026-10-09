const {before, after, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, getDocs, collection, collectionGroup, query, where, and, or, orderBy, limit, serverTimestamp, runTransaction} = require('firebase/firestore');
const {ref, uploadBytes, getMetadata, deleteObject} = require('firebase/storage');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-prox-audit', firestore: {
    host: '127.0.0.1', port: 8088,
    rules: readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8'),
  }, storage: {host: '127.0.0.1', port: 9198, rules: readFileSync(path.join(__dirname, '../../storage.rules'), 'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  // rules-unit-testing's clearStorage deletes root items but ignores prefixes.
  // Clear nested chatMedia fixtures too: uploads deliberately cannot overwrite.
  await env.withSecurityRulesDisabled(async context => {
    async function clearPrefix(prefix) {
      const {items, prefixes} = await prefix.listAll();
      await Promise.all([...items.map(item => item.delete()), ...prefixes.map(clearPrefix)]);
    }
    await clearPrefix(context.storage().ref());
  });
});
const db = uid => env.authenticatedContext(uid).firestore();

test('suspension stops Firestore and Storage with cached tokens; enforcement and disable flags are server-owned', async () => {
  await seed({'users/alice': {disabled: true}, 'accountEnforcements/alice': {status: 'suspended'}});
  await assertFails(getDoc(doc(db('alice'), 'users/alice')));
  await assertFails(setDoc(doc(db('alice'), 'users/alice/settings/matching'), {partyScope: 'public'}));
  await assertFails(updateDoc(doc(db('alice'), 'accountEnforcements/alice'), {status: 'active'}));
  await assertSucceeds(getDoc(doc(db('alice'), 'accountEnforcements/alice')));
  await assertFails(uploadBytes(ref(env.authenticatedContext('alice').storage(), 'profiles/alice/selfie.jpg'),
    new Uint8Array([1, 2, 3]), {contentType: 'image/jpeg'}));
  await seed({'accountEnforcements/alice': {status: 'active'}});
  await assertFails(updateDoc(doc(db('alice'), 'users/alice'), {disabled: false}));
  await assertFails(setDoc(doc(db('alice'), 'functionRateLimits/alice'), {count: 0}));
  await assertFails(setDoc(doc(db('alice'), 'accountModerationAudit/fake'), {action: 'restore'}));
  await assertFails(getDoc(doc(db('alice'), 'accountModerationAudit/fake')));
  await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice'), {displayName: 'Allowed profile edit'}));
});

test('unverified new accounts cannot forge trust, recruit, chat or create a meetup, but can complete a profile and ask support', async () => {
  await seed({'users/newbie': {referralTrustRequired: true, referralInPersonVerified: false}});
  await assertFails(updateDoc(doc(db('newbie'), 'users/newbie'), {referralInPersonVerified: true}));
  await assertFails(updateDoc(doc(db('newbie'), 'users/newbie'), {referralTrustRequired: false}));
  await assertFails(updateDoc(doc(db('newbie'), 'users/newbie'), {referrer: 'forged'}));
  await assertFails(setDoc(doc(db('newbie'), 'referralCodes/INV123'), {referrerUid: 'newbie', active: true}));
  await assertFails(setDoc(doc(db('newbie'), 'chats/newbie__other'), {participants: ['newbie', 'other'], isGroup: false}));
  await assertFails(setDoc(doc(db('newbie'), 'meetups/new'), {aUid: 'newbie', bUid: 'other', status: 'requested'}));
  await assertSucceeds(updateDoc(doc(db('newbie'), 'users/newbie'), {displayName: 'New user'}));
  await assertSucceeds(setDoc(doc(db('newbie'), 'supportTickets/new'), {uid: 'newbie', subject: 'QR help', status: 'open'}));
});

test('mentor progress is private to the direct referrer and all mentor projections are server-owned', async () => {
  await seed({
    'users/newbie': {referrer: 'mentor', root_referrer: 'ancestor'},
    'users/mentor/mentorReferrals/newbie': {uid: 'newbie', mentorUid: 'mentor', profileComplete: true, meetupsCompleted: 1},
    'users/newbie/referralMentor/current': {mentorUid: 'mentor', role: 'mentor', partyAdded: true},
  });
  await assertSucceeds(getDoc(doc(db('mentor'), 'users/mentor/mentorReferrals/newbie')));
  await assertFails(getDocs(collection(db('mentor'), 'users/mentor/mentorReferrals')));
  await assertSucceeds(getDoc(doc(db('newbie'), 'users/newbie/referralMentor/current')));
  await assertSucceeds(getDoc(doc(db('other'), 'users/other/referralMentor/current')));
  for (const outsider of ['other', 'ancestor', 'newbie']) {
    await assertFails(getDoc(doc(db(outsider), 'users/mentor/mentorReferrals/newbie')));
  }
  await assertFails(getDoc(doc(db('mentor'), 'users/newbie/referralMentor/current')));
  await assertFails(setDoc(doc(db('mentor'), 'users/mentor/mentorReferrals/forged'), {uid: 'forged'}));
  await assertFails(updateDoc(doc(db('newbie'), 'users/newbie/referralMentor/current'), {mentorUid: 'other'}));
  await assertFails(setDoc(doc(db('mentor'), 'referralMentorNudges/forged'), {fromUid: 'mentor', toUid: 'newbie'}));
  await seed({'users/newbie/blocks/mentor': {uid: 'mentor'}});
  await assertFails(getDoc(doc(db('mentor'), 'users/mentor/mentorReferrals/newbie')));
  await assertFails(getDoc(doc(db('newbie'), 'users/newbie/referralMentor/current')));
});

test('mentor contact does not expose Party-private profiles or unlock trust before meeting', async () => {
  await seed({
    'users/mentor/party/newbie': {uid: 'newbie', mutual: true, metInPerson: false, source: 'referralMentor'},
    'users/newbie/party/mentor': {uid: 'mentor', mutual: true, metInPerson: false, source: 'referralMentor'},
    'users/newbie/partyProfile/current': {phone: 'private'},
    'users/newbie': {referrer: 'mentor'},
  });
  await assertFails(getDoc(doc(db('mentor'), 'users/newbie/partyProfile/current')));
  await assertFails(getDoc(doc(db('mentor'), 'users/newbie')));
  await assertSucceeds(setDoc(doc(db('newbie'), 'chats/mentor__newbie'), {participants: ['mentor', 'newbie'], isGroup: false}));
  await assertSucceeds(setDoc(doc(db('mentor'), 'chats/mentor__newbie/messages/help'), {from: 'mentor', to: 'newbie', text: 'How can I help?', kind: 'text'}));
});

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

test('active meetup cancellation requires actor-scoped mutual cancel handshake evidence', async () => {
  await seed({'meetups/handshake': {aUid: 'alice', bUid: 'bob', status: 'live', aArrived: false, bArrived: false}});
  const ref = doc(db('alice'), 'meetups/handshake');
  await assertFails(updateDoc(ref, {status: 'cancelled'}));

  await seed({'meetups/handshake': {aUid: 'alice', bUid: 'bob', status: 'live', aArrived: false, bArrived: false}});
  await assertFails(updateDoc(ref, {status: 'cancelled', cancelHandshakeByUid: {
    alice: {requestId: 'alice-spoof'},
    bob: {requestId: 'bob-spoof'},
  }}));

  await seed({'meetups/handshake': {aUid: 'alice', bUid: 'bob', status: 'live', aArrived: false, bArrived: false}});
  await assertSucceeds(updateDoc(ref, {cancelHandshakeByUid: {alice: {requestId: 'alice-intent'}}}));
  await assertSucceeds(updateDoc(doc(db('bob'), 'meetups/handshake'), {cancelHandshakeByUid: {
    alice: {requestId: 'alice-intent'},
    bob: {requestId: 'bob-intent'},
  }}));
  await assertSucceeds(updateDoc(ref, {status: 'cancelled'}));
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
  await assertFails(setDoc(doc(db('alice'), 'users/alice/party/bob'), {uid: 'bob', mutual: false}));
  await assertFails(updateDoc(doc(db('alice'), 'users/alice/party/bob'), {mutual: true}));
  await seed({'users/alice/referrals/bob': {uid: 'bob', meetupsCompleted: 1, inPersonVerified: true}});
  await assertFails(updateDoc(doc(db('alice'), 'users/alice/referrals/bob'), {meetupsCompleted: 4}));
});

test('Party referral badges can read exact own invitee documents, including absent rows, without a group grant', async () => {
  await seed({
    'users/referrer/referrals/alice': {uid: 'alice', partyInPersonQrRequested: true, inPersonVerified: true},
    'users/referrer/referrals/bob': {uid: 'bob', partyInPersonQrRequested: true, inPersonVerified: true},
    'users/other/referrals/alice': {uid: 'alice', partyInPersonQrRequested: true, inPersonVerified: false},
  });
  const received = await assertSucceeds(getDoc(doc(db('alice'), 'users/referrer/referrals/alice')));
  assert.equal(received.data().inPersonVerified, true);
  const pending = await assertSucceeds(getDoc(doc(db('alice'), 'users/other/referrals/alice')));
  assert.equal(pending.data().inPersonVerified, false);
  const missing = await assertSucceeds(getDoc(doc(db('alice'), 'users/missing/referrals/alice')));
  assert.equal(missing.exists(), false);
  await assertSucceeds(getDoc(doc(db('referrer'), 'users/referrer/referrals/alice')));
  const owned = await assertSucceeds(getDocs(collection(db('referrer'), 'users/referrer/referrals')));
  assert.equal(owned.size, 2);
  await assertFails(getDoc(doc(db('alice'), 'users/referrer/referrals/bob')));
  await assertFails(getDoc(doc(db('mallory'), 'users/referrer/referrals/alice')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/referrer/referrals/alice')));
  await assertFails(getDocs(query(collectionGroup(db('alice'), 'referrals'), where('uid', '==', 'alice'), limit(20))));
});

test('account deletion revokes exact referral reads even when the invitee document is absent', async () => {
  await seed({
    'users/referrer/referrals/alice': {uid: 'alice', partyInPersonQrRequested: true, inPersonVerified: true},
    'accountDeletions/alice': {status: 'processing'},
    'accountDeletions/referrer': {status: 'processing'},
  });
  await assertFails(getDoc(doc(db('alice'), 'users/referrer/referrals/alice')));
  await assertFails(getDoc(doc(db('alice'), 'users/missing/referrals/alice')));
  await assertFails(getDoc(doc(db('referrer'), 'users/referrer/referrals/alice')));
});

test('owner-written business descendants cannot become readable Party referrals through a group query', async () => {
  const nested = 'users/referrer/business/draft/referrals/alice';
  await assertSucceeds(setDoc(doc(db('referrer'), nested), {
    uid: 'alice', partyInPersonQrRequested: true, inPersonVerified: true,
  }));
  await assertSucceeds(getDoc(doc(db('referrer'), nested)));
  await assertFails(getDoc(doc(db('alice'), nested)));
  await assertFails(getDocs(query(collectionGroup(db('alice'), 'referrals'),
    where('uid', '==', 'alice'), where('partyInPersonQrRequested', '==', true),
    where('inPersonVerified', '==', true), limit(20))));
  const canonical = doc(db('referrer'), 'users/referrer/referrals/alice');
  await assertFails(setDoc(canonical, {uid: 'alice', inPersonVerified: true}));
  await seed({'users/referrer/referrals/alice': {uid: 'alice', partyInPersonQrRequested: true, inPersonVerified: false}});
  await assertFails(updateDoc(canonical, {inPersonVerified: true}));
  await assertFails(updateDoc(doc(db('alice'), 'users/referrer/referrals/alice'), {partyInPersonQrRequested: true}));
});

test('referral reminder merges and legacy Party grant notes preserve server-owned verification and rewards', async () => {
  const reminder = doc(db('referrer'), 'users/referrer/referrals/reminder_only');
  await assertSucceeds(setDoc(reminder, {lastReminderAt: serverTimestamp()}, {merge: true}));
  await assertSucceeds(setDoc(reminder, {lastReminderAt: serverTimestamp()}, {merge: true}));
  assert.equal((await assertSucceeds(getDoc(reminder))).data().uid, undefined);
  await seed({'users/referrer/referrals/alice': {
    uid: 'alice', inPersonVerified: true, rewardEligible: true,
    partyInPersonQrRequested: true, meetupsCompleted: 1,
  }});
  const verified = doc(db('referrer'), 'users/referrer/referrals/alice');
  await assertSucceeds(updateDoc(verified, {lastReminderAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(verified, {partyInPersonQrGrantedAt: serverTimestamp(), updatedAt: serverTimestamp()}));
  for (const [field, value] of Object.entries({
    inPersonVerified: false, rewardEligible: false, rewardGranted: true,
    rewardCredited: true, meetupsCompleted: 5, referralsCompleted: 5,
  })) {
    await assertFails(updateDoc(verified, {[field]: value}));
  }
  await assertFails(deleteDoc(verified));
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
  await seed({'users/alice/party/bob':{mutual:true,metInPerson:true},'users/bob/party/alice':{mutual:true,metInPerson:true}});
  await assertSucceeds(getDoc(doc(db('bob'),'users/alice/partyProfile/sharing')));
  await seed({'users/bob/blocks/alice':{uid:'alice'}});
  await assertFails(getDoc(doc(db('bob'),'users/alice/partyProfile/sharing')));
});


test('background coordinates are private, bound to the opted-in device and reject stale or fabricated metadata', async () => {
  await seed({'users/alice/settings/backgroundMatching': {enabled: true, deviceId: 'phone'}});
  const sample = {enabled: true, deviceId: 'phone', latitude: 40, longitude: -74,
    locationAt: new Date(), receivedAt: serverTimestamp(), accuracyMeters: 150, speedMps: 0,
    utcOffsetMinutes: -240, expiresAt: new Date(Date.now() + 30 * 60000)};
  const ref = doc(db('alice'), 'users/alice/backgroundPresence/current');
  await assertSucceeds(setDoc(ref, sample));
  await assertSucceeds(getDoc(ref));
  await assertFails(getDoc(doc(db('bob'), 'users/alice/backgroundPresence/current')));
  await assertFails(setDoc(ref, {...sample, deviceId: 'other-phone'}));
  await assertFails(setDoc(ref, {...sample, receivedAt: new Date(0)}));
  await assertFails(setDoc(ref, {...sample, locationAt: new Date(Date.now() - 31 * 60000)}));
  await assertFails(setDoc(ref, {...sample, latitude: 200}));
  await assertFails(setDoc(ref, {...sample, accuracyMeters: 500}));
  await assertFails(setDoc(ref, {...sample, locationHistory: []}));
  await assertFails(getDocs(query(collectionGroup(db('bob'), 'backgroundPresence'), where('enabled', '==', true))));
  await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice/settings/backgroundMatching'), {enabled: false}));
  await assertFails(setDoc(ref, sample));
  await assertSucceeds(deleteDoc(ref));
});

test('verified Party access closes immediately when a peer starts deleting their account', async () => {
  await seed({
    'users/alice/party/bob': {mutual: true, metInPerson: true},
    'users/bob/party/alice': {mutual: true, metInPerson: true},
    'users/alice/partyProfile/sharing': {phone: '555-0100'},
  });
  await assertSucceeds(getDoc(doc(db('bob'), 'users/alice/partyProfile/sharing')));
  await seed({'accountDeletions/alice': {status: 'processing'}});
  await assertFails(getDoc(doc(db('bob'), 'users/alice/partyProfile/sharing')));
});

test('alert budgets, outbox and opportunities cannot be reset or forged by a client', async () => {
  for (const collection of ['backgroundAlertState', 'backgroundAlertPairs', 'backgroundScanState', 'backgroundAlertOutbox', 'backgroundOpportunities']) {
    const ref = doc(db('alice'), `users/alice/${collection}/current`);
    await seed({[`users/alice/${collection}/current`]: {sentAt: [1], otherUid: 'bob'}});
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, {sentAt: [], otherUid: 'carol'}));
    await assertFails(deleteDoc(ref));
  }
});

test('public matching access and in-person proofs are server-owned and public choice needs a verified unlock', async () => {
  for (const name of ['matchingLocations/alice', 'matchingConfig/publicDiscovery', 'partyInPersonSessions/session',
    'partyInPersonCodes/code', 'partyInPersonRateLimits/alice']) {
    await assertFails(setDoc(doc(db('alice'), name), {publicUnlocked: true}));
    await assertFails(getDoc(doc(db('alice'), name)));
  }
  const access = doc(db('alice'), 'users/alice/matchingAccess/current');
  await assertFails(setDoc(access, {publicUnlocked: true}));
  await seed({'users/alice/matchingAccess/current': {publicUnlocked: false}});
  await assertSucceeds(getDoc(access));
  await assertFails(getDoc(doc(db('bob'), 'users/alice/matchingAccess/current')));
  const settings = doc(db('alice'), 'users/alice/settings/matching');
  await assertSucceeds(setDoc(settings, {partyScope: 'none'}));
  await assertSucceeds(updateDoc(settings, {modeKind: 'listen'}));
  await assertSucceeds(setDoc(settings, {partyScope: 'tree'}));
  await assertFails(updateDoc(settings, {partyScope: 'public'}));
  await seed({'users/alice/matchingAccess/current': {publicUnlocked: true}});
  await assertSucceeds(updateDoc(settings, {partyScope: 'public'}));
  await assertSucceeds(updateDoc(settings, {partyScope: 'tree'}));
  await assertFails(setDoc(doc(db('alice'), 'users/alice/party/bob'), {uid: 'bob', mutual: true, metInPerson: true}));
  for (const kind of ['partyPresence', 'partyHandshake', 'partyAddRequest']) {
    await assertFails(setDoc(doc(db('alice'), `meetupRequests/${kind}`), {aUid: 'alice', bUid: 'bob', kind}));
  }
});

test('enrollment presence stamps cannot be manufactured by clients', async () => {
  const presence = doc(db('alice'), 'users/alice/presence/current');
  const {GeoPoint} = require('firebase/firestore');
  await assertSucceeds(setDoc(presence, {geopoint: new GeoPoint(40, -74), ts: serverTimestamp()}));
  await assertFails(updateDoc(presence, {ts: new Date(0)}));
  await assertSucceeds(deleteDoc(presence));
});


test('chat creation preflight is allowed and the second participant can open without rewriting the pair', async () => {
  const aliceDb = db('alice');
  const aliceRef = doc(aliceDb, 'chats/alice_bob');
  await assertSucceeds(runTransaction(aliceDb, async tx => {
    const row = await tx.get(aliceRef);
    assert.equal(row.exists(), false);
    tx.set(aliceRef, {participants: ['alice', 'bob'], chatGate: {status: 'requested', requestedBy: 'alice'}});
  }));
  const bobDb = db('bob');
  const bobRef = doc(bobDb, 'chats/alice_bob');
  await assertFails(setDoc(bobRef, {participants: ['bob', 'alice'], chatGate: {status: 'requested', requestedBy: 'bob'}}, {merge: true}));
  await assertSucceeds(runTransaction(bobDb, async tx => {
    const row = await tx.get(bobRef);
    assert.deepEqual(row.data().participants, ['alice', 'bob']);
    assert.equal(row.data().chatGate.requestedBy, 'alice');
  }));
  await assertFails(getDoc(doc(db('mallory'), 'chats/alice_bob')));
});


test('Listen and legacy requests cannot be expired by the old sixty-second client timer', async () => {
  for (const [id, gate] of [
    ['listen', {modeKind: 'listen', responseWindowSeconds: 86400}],
    ['legacy', {}],
    ['passive', {modeKind: 'normal', responseWindowSeconds: 86400}],
  ]) {
    await seed({[`chats/${id}`]: {participants: ['alice', 'bob'], chatGate: {status: 'requested', requestedBy: 'alice', requestedAt: new Date(Date.now() - 120000), ...gate}}});
    await assertFails(updateDoc(doc(db('bob'), `chats/${id}`), {'chatGate.status': 'expired', 'chatGate.expiredBySystem': true}));
    await assertSucceeds(updateDoc(doc(db('bob'), `chats/${id}`), {'chatGate.status': 'accepted', 'chatGate.acceptedBy': 'bob'}));
  }
  await seed({'chats/active': {participants: ['alice', 'bob'], chatGate: {status: 'requested', requestedBy: 'alice', requestedAt: new Date(Date.now() - 120000), modeKind: 'normal', responseWindowSeconds: 60}}});
  await assertSucceeds(updateDoc(doc(db('bob'), 'chats/active'), {'chatGate.status': 'expired', 'chatGate.expiredBySystem': true}));
});

test('timed-out requests can explicitly renew without reopening declined or closed chats', async () => {
  const old = {participants: ['alice', 'bob'], chatGate: {status: 'expired', expiredBySystem: true, requestedBy: 'alice', requestedAt: new Date(Date.now() - 120000)}};
  await seed({'chats/renew': old});
  const ref = doc(db('bob'), 'chats/renew');
  const renewal = {chatGate: {status: 'requested', requestedBy: 'bob', requestedAt: serverTimestamp(), modeKind: 'listen', responseWindowSeconds: 86400}};
  await assertSucceeds(updateDoc(ref, renewal));
  await assertFails(updateDoc(ref, {'chatGate.requestedBy': 'alice'}));
  await assertFails(updateDoc(ref, {'chatGate.responseWindowSeconds': 60}));
  for (const data of [
    {...old, closedAt: new Date()},
    {...old, chatGate: {...old.chatGate, declinedBy: 'alice'}},
    {...old, chatGate: {...old.chatGate, acceptedAt: new Date()}},
    {...old, chatGate: {...old.chatGate, status: 'declined'}},
  ]) {
    await seed({'chats/renew': data});
    await assertFails(updateDoc(ref, renewal));
  }
  await seed({'chats/renew': old, 'users/alice/blocks/bob': {uid: 'bob'}});
  await assertFails(updateDoc(ref, renewal));
});

test('chat photos are participant-private, immutable and only their owner can discard them', async () => {
  await seed({'chats/media-private': {participants: ['alice', 'bob'], isGroup: false}});
  const path = 'chatMedia/media-private/alice-private-photo.png';
  const alice = env.authenticatedContext('alice').storage();
  const bob = env.authenticatedContext('bob').storage();
  const outsider = env.authenticatedContext('mallory').storage();
  const metadata = {contentType: 'image/png', customMetadata: {ownerUid: 'alice', chatId: 'media-private'}};
  await assertSucceeds(uploadBytes(ref(alice, path), new Uint8Array([137, 80, 78, 71]), metadata));
  await assertSucceeds(getMetadata(ref(bob, path)));
  await assertFails(getMetadata(ref(outsider, path)));
  await assertFails(deleteObject(ref(bob, path)));
  await assertFails(uploadBytes(ref(alice, path), new Uint8Array([1]), metadata));
  await assertFails(uploadBytes(ref(bob, 'chatMedia/media-private/alice-forged.png'), new Uint8Array([1]), metadata));
  await assertFails(uploadBytes(ref(alice, 'chatMedia/media-private/alice-missing-owner.png'), new Uint8Array([1]), {contentType: 'image/png'}));
  await seed({'chats/media-private': {participants: ['alice', 'bob'], closedAt: new Date()}});
  await assertFails(uploadBytes(ref(alice, 'chatMedia/media-private/alice-after-close.png'), new Uint8Array([1]), metadata));
  await assertSucceeds(deleteObject(ref(alice, path)));
});

test('chat media access is revoked after removal from participants or account deletion', async () => {
  await seed({'chats/media-revocation': {participants: ['alice', 'bob']}});
  const alice = env.authenticatedContext('alice').storage();
  const bob = env.authenticatedContext('bob').storage();
  const path = 'chatMedia/media-revocation/alice-revocation.png';
  await assertSucceeds(uploadBytes(ref(alice, path), new Uint8Array([1]), {contentType: 'image/png', customMetadata: {ownerUid: 'alice', chatId: 'media-revocation'}}));
  await seed({'chats/media-revocation': {participants: ['alice']}});
  await assertFails(getMetadata(ref(bob, path)));
  await seed({'accountDeletions/alice': {status: 'processing'}});
  await assertFails(getMetadata(ref(alice, path)));
  await assertFails(deleteObject(ref(alice, path)));
});

test('business automation control, jobs, receipts and consents cannot be forged or read by clients', async () => {
  const paths = ['businessAutomation/config', 'businessAutomationJobs/job', 'businessAutomationReceipts/receipt', 'businessAutomationConsents/alice'];
  await seed(Object.fromEntries(paths.map(path => [path, {uid: 'alice', enabled: true}])));
  for (const path of paths) {
    await assertFails(getDoc(doc(db('alice'), path)));
    await assertFails(setDoc(doc(db('alice'), path), {uid: 'alice', enabled: true}));
    await assertFails(deleteDoc(doc(db('alice'), path)));
  }
});
