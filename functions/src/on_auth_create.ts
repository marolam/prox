import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

export const onAuthCreate = functions.auth.user().onCreate(async (user) => {
  const uid = user.uid;
  if (!uid) return;

  const ref = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const [snap, deletion] = await tx.getAll(ref, db.doc(`accountDeletions/${uid}`));
    if (deletion.exists) return;
    const data = snap.data() || {};
    if (data.createdAt instanceof admin.firestore.Timestamp) return;

    tx.set(
      ref,
      {
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
});
