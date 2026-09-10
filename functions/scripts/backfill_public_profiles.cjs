// Default is read-only. Deployment preparation must inspect this report before --apply.
const admin = require('firebase-admin');
const projectArg = process.argv.find(arg => arg.startsWith('--project='));
if (!projectArg) throw new Error('Pass --project=<firebase-project-id>. Default is a read-only dry run.');
const projectId = projectArg.split('=')[1];
const apply = process.argv.includes('--apply');
admin.initializeApp({projectId});
const db = admin.firestore();
const {publicProfile, publicProfilesEqual, syncPublicProfile} = require('../lib/public_profiles');
(async () => {
  let cursor;
  let scanned = 0;
  let changed = 0;
  for (;;) {
    let query = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const account of page.docs) {
      scanned++;
      const settings = await db.doc(`users/${account.id}/settings/matching`).get();
      const projected = publicProfile(account.id, account.data(), settings.data() || {});
      const previous = await db.doc(`publicProfiles/${account.id}`).get();
      if (publicProfilesEqual(previous.data(), projected)) continue;
      changed++;
      if (apply) await syncPublicProfile(account.id);
    }
    cursor = page.docs.at(-1);
  }
  console.log(JSON.stringify({projectId, mode: apply ? 'apply' : 'dry-run', scanned, changed}));
  await admin.app().delete();
})().catch(error => {console.error(error.message); process.exitCode = 1;});
