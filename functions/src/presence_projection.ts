import * as admin from 'firebase-admin';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

export async function syncPresenceCoordinates(uid: string): Promise<void> {
  const reference = db.doc(`users/${uid}/presence/current`);
  await db.runTransaction(async tx => {
    const [current, deletion] = await tx.getAll(reference, db.doc(`accountDeletions/${uid}`));
    const data = current.data();
    if (!data || deletion.exists || !(data.geopoint instanceof admin.firestore.GeoPoint)) return;
    const {latitude, longitude} = data.geopoint;
    if (data.kind === 'current' && data.latitude === latitude && data.longitude === longitude) return;
    tx.update(reference, {kind: 'current', latitude, longitude});
  });
}

export const onPresenceCoordinates = onDocumentWritten({document: 'users/{uid}/presence/current', retry: true}, async event => {
  await syncPresenceCoordinates(event.params.uid);
});
