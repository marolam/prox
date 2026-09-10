// Read-only by default. Explicit --apply is reserved for an approved migration.
const admin = require('firebase-admin');
const projectArg = process.argv.find(arg => arg.startsWith('--project='));
if (!projectArg) throw new Error('Pass --project=<firebase-project-id>. Default is a read-only dry run.');
const projectId = projectArg.split('=')[1];
const apply = process.argv.includes('--apply');
admin.initializeApp({projectId});
const db = admin.firestore();
const {syncPresenceCoordinates} = require('../lib/presence_projection');
(async () => {
  let cursor;
  let scanned = 0;
  let changed = 0;
  for (;;) {
    let query = db.collectionGroup('presence').orderBy(admin.firestore.FieldPath.documentId()).limit(200);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const presence of page.docs) {
      const parts = presence.ref.path.split('/');
      if (parts.length !== 4 || parts[0] !== 'users' || parts[3] !== 'current') continue;
      scanned++;
      const data = presence.data();
      if (!(data.geopoint instanceof admin.firestore.GeoPoint)) continue;
      if (data.latitude === data.geopoint.latitude && data.longitude === data.geopoint.longitude && data.kind === 'current') continue;
      changed++;
      if (apply) await syncPresenceCoordinates(parts[1]);
    }
    cursor = page.docs.at(-1);
  }
  console.log(JSON.stringify({projectId, mode: apply ? 'apply' : 'dry-run', scanned, changed}));
  await admin.app().delete();
})().catch(error => {console.error(error.message); process.exitCode = 1;});
