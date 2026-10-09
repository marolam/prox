import * as admin from 'firebase-admin';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {connectionId} from '../party_connections';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Read current state inside the transaction, and write only changed projections.
// This tolerates retries and out-of-order membership events without trigger loops.
export async function reconcileVerifiedPartyConnection(uid: string, friendUid: string): Promise<boolean> {
  if (!uid || !friendUid || uid.includes('/') || friendUid.includes('/') || uid === friendUid || ['current', 'partySettings'].includes(friendUid)) return false;
  const mine = db.doc(`users/${uid}/party/${friendUid}`);
  const theirs = db.doc(`users/${friendUid}/party/${uid}`);
  return db.runTransaction(async tx => {
    const connection = db.doc(`partyConnections/${connectionId(uid, friendUid)}`);
    const [a, b, deletedA, deletedB, blockA, blockB, consent] = await tx.getAll(mine, theirs,
      db.doc(`accountDeletions/${uid}`), db.doc(`accountDeletions/${friendUid}`),
      db.doc(`users/${uid}/blocks/${friendUid}`), db.doc(`users/${friendUid}/blocks/${uid}`), connection);
    const receipt = consent.data();
    const members = Array.isArray(receipt?.members) ? receipt!.members : [];
    let verified = receipt?.status === 'connected' && members.length === 2 && members.includes(uid) && members.includes(friendUid) &&
      receipt?.decisions?.[uid] === 'add' && receipt?.decisions?.[friendUid] === 'add' &&
      ['completedMeetup', 'inPersonCode', 'referralQr'].includes(receipt?.proof?.kind);
    let mentorContact = false;
    if (receipt?.status === 'connected' && receipt.proof?.kind === 'referralMentor' &&
        members.length === 2 && members.includes(uid) && members.includes(friendUid)) {
      const invitee = receipt.proof.inviteeUid;
      const mentor = receipt.proof.mentorUid;
      if ([uid, friendUid].includes(invitee) && [uid, friendUid].includes(mentor) && invitee !== mentor) {
        const [user, contact] = await tx.getAll(db.doc(`users/${invitee}`), db.doc(`users/${invitee}/referralMentor/current`));
        mentorContact = user.data()?.referrer === mentor && contact.data()?.partyRequested === true &&
          receipt.decisions?.[uid] === 'add' && receipt.decisions?.[friendUid] === 'add';
      }
    }
    // Earlier server-created post-meetup receipts predate proof fields. Validate
    // their meetup before upgrading; reciprocal legacy client writes alone do not prove a meeting.
    if (!verified && receipt?.status === 'connected' && members.length === 2 && members.includes(uid) && members.includes(friendUid) && receipt.decisions?.[uid] === 'add' &&
        receipt.decisions?.[friendUid] === 'add' && typeof receipt.chatId === 'string' && receipt.chatId.length > 0 && !receipt.chatId.includes('/')) {
      const meetup = (await tx.get(db.doc(`meetups/${receipt.chatId}`))).data();
      verified = meetup?.status === 'completed' && ((meetup.aUid === uid && meetup.bUid === friendUid) ||
        (meetup.aUid === friendUid && meetup.bUid === uid));
      if (verified) tx.update(connection, {proof: {kind: 'completedMeetup', chatId: receipt.chatId}, source: 'postMeetup'});
    }
    if (blockA.exists || blockB.exists || deletedA.exists || deletedB.exists || (!verified && !mentorContact) || !a.exists || !b.exists) {
      if (a.exists) tx.delete(mine);
      if (b.exists) tx.delete(theirs);
      if (consent.data()?.status === 'connected') tx.update(connection, {status: 'removed', decisions: {}, updatedAt: admin.firestore.Timestamp.now()});
      return false;
    }
    const id = connection.id;
    if (a.data()?.mutual !== true || a.data()?.metInPerson !== verified || a.data()?.uid !== friendUid || a.data()?.connectionId !== id) {
      tx.update(mine, {mutual: true, metInPerson: verified, uid: friendUid, connectionId: id});
    }
    if (b.data()?.mutual !== true || b.data()?.metInPerson !== verified || b.data()?.uid !== uid || b.data()?.connectionId !== id) {
      tx.update(theirs, {mutual: true, metInPerson: verified, uid, connectionId: id});
    }
    return true;
  });
}

export const onPartyWrite = onDocumentWritten({document: 'users/{uid}/party/{friendUid}', retry: true}, async event => {
  await reconcileVerifiedPartyConnection(event.params.uid, event.params.friendUid);
});
