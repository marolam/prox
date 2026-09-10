import * as admin from 'firebase-admin';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Read current state inside the transaction, and write only changed projections.
// This tolerates retries and out-of-order membership events without trigger loops.
export const onPartyWrite = onDocumentWritten({document: 'users/{uid}/party/{friendUid}', retry: true}, async event => {
  const {uid, friendUid} = event.params;
  if (uid === friendUid || ['current', 'partySettings'].includes(friendUid)) return;
  const mine = db.doc(`users/${uid}/party/${friendUid}`);
  const theirs = db.doc(`users/${friendUid}/party/${uid}`);
  await db.runTransaction(async tx => {
    const [a, b, deletedA, deletedB] = await tx.getAll(mine, theirs, db.doc(`accountDeletions/${uid}`), db.doc(`accountDeletions/${friendUid}`));
    const mutual = a.exists && b.exists && !deletedA.exists && !deletedB.exists;
    if (a.exists && (a.data()?.mutual !== mutual || a.data()?.uid !== friendUid)) tx.update(mine, {mutual, uid: friendUid});
    if (b.exists && (b.data()?.mutual !== mutual || b.data()?.uid !== uid)) tx.update(theirs, {mutual, uid});
  });
});
