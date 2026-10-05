const {before, after, test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, getDocs, collection, query, where, updateDoc, deleteDoc} = require('firebase/firestore');
let env;
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-prox-audit', firestore: {host: '127.0.0.1', port: 8088,
    rules: readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8')}});
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'businessOffers/offer0001'), {uid: 'owner', status: 'pending_review', title: 'Private offer'});
    await setDoc(doc(db, 'businessOffers/offer0002'), {uid: 'other', status: 'pending_review', title: 'Other private offer'});
    await setDoc(doc(db, 'publicBusinessOffers/offer0001'), {uid: 'owner', status: 'active', title: 'Projection'});
    for (const name of ['businessOfferRequests', 'businessOfferBudgets', 'businessOfferTombstones']) await setDoc(doc(db, `${name}/private001`), {uid: 'owner'});
  });
});
after(async () => { await env.cleanup(); });
test('owners read only their drafts and administrators read the moderation queue', async () => {
  const owner = env.authenticatedContext('owner').firestore();
  const admin = env.authenticatedContext('operator', {admin: true}).firestore();
  await assertSucceeds(getDoc(doc(owner, 'businessOffers/offer0001')));
  await assertFails(getDoc(doc(owner, 'businessOffers/offer0002')));
  const owned = await assertSucceeds(getDocs(query(collection(owner, 'businessOffers'), where('uid', '==', 'owner'))));
  assert.equal(owned.size, 1);
  await assertSucceeds(getDocs(query(collection(admin, 'businessOffers'), where('status', '==', 'pending_review'))));
  await assertFails(getDocs(collection(owner, 'businessOffers')));
});
test('neither owners nor administrators can forge publication or directly read protected audience projections', async () => {
  for (const context of [env.authenticatedContext('owner'), env.authenticatedContext('operator', {admin: true}), env.unauthenticatedContext()]) {
    const db = context.firestore();
    await assertFails(updateDoc(doc(db, 'businessOffers/offer0001'), {status: 'active'}));
    await assertFails(setDoc(doc(db, 'businessOffers/forged001'), {uid: 'owner', status: 'active'}));
    await assertFails(deleteDoc(doc(db, 'businessOffers/offer0001')));
    await assertFails(getDoc(doc(db, 'publicBusinessOffers/offer0001')));
    await assertFails(setDoc(doc(db, 'publicBusinessOffers/forged001'), {status: 'active'}));
    for (const name of ['businessOfferRequests', 'businessOfferBudgets', 'businessOfferTombstones']) {
      await assertFails(getDoc(doc(db, `${name}/private001`)));
      await assertFails(setDoc(doc(db, `${name}/forged001`), {uid: 'owner'}));
    }
  }
});
