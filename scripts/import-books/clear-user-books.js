/**
 * Delete userBooks for a given Firebase user (wellread database).
 *
 * Prerequisites:
 *   Firebase service account key at scripts/import-books/service-account.json
 *   (same as import.js - Firebase Console → Project Settings → Service Accounts → Generate new private key)
 *
 * Run (all shelves):
 *   FIREBASE_UID="..." node clear-user-books.js
 * Or resolve uid by email:
 *   FIREBASE_EMAIL="you@example.com" node clear-user-books.js
 * Only finished / read shelf (status in Firestore is "Read"):
 *   FIREBASE_EMAIL="you@example.com" STATUS="Read" node clear-user-books.js
 *
 * Optional: GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 */

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const __dirname = dirname(fileURLToPath(import.meta.url));

const FIREBASE_UID = process.env.FIREBASE_UID;
const FIREBASE_EMAIL = process.env.FIREBASE_EMAIL;
/** If set, only delete documents with this status (e.g. "Read", "Queue", "Currently Reading"). */
const STATUS = process.env.STATUS;
const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_APPLICATION_CREDENTIALS || join(__dirname, 'service-account.json');

if (!FIREBASE_UID && !FIREBASE_EMAIL) {
  console.error(
    'Set FIREBASE_UID or FIREBASE_EMAIL. Example: FIREBASE_EMAIL="you@example.com" STATUS="Read" node clear-user-books.js'
  );
  process.exit(1);
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
} catch (e) {
  console.error('Missing or invalid service account JSON at', SERVICE_ACCOUNT_PATH);
  console.error('Download from Firebase Console → Project Settings → Service Accounts → Generate new private key.');
  process.exit(1);
}

const app = initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore(app, 'wellread');

const BATCH_SIZE = 500;

async function syncTotalBooksReadFromShelf(uid) {
  const col = db.collection('userBooks');
  const remaining = await col.where('userId', '==', uid).where('status', '==', 'Read').get();
  await db.collection('users').doc(uid).set({ totalBooksRead: remaining.size }, { merge: true });
  console.log('Synced users/', uid, 'totalBooksRead →', remaining.size);
}

async function main() {
  let uid = FIREBASE_UID;
  if (!uid) {
    const auth = getAuth(app);
    const user = await auth.getUserByEmail(FIREBASE_EMAIL);
    uid = user.uid;
    console.log('Resolved', FIREBASE_EMAIL, '→ uid', uid);
  }

  const col = db.collection('userBooks');
  let query = col.where('userId', '==', uid);
  if (STATUS) {
    query = query.where('status', '==', STATUS);
  }
  const snapshot = await query.get();
  const count = snapshot.size;
  if (count === 0) {
    console.log('No userBooks found for', uid, STATUS ? `(status=${STATUS})` : '(all statuses)');
    if (STATUS === 'Read') {
      await syncTotalBooksReadFromShelf(uid);
    }
    return;
  }
  console.log('Deleting', count, 'userBooks for user', uid, STATUS ? `(status=${STATUS})` : '');
  const refs = snapshot.docs.map((d) => d.ref);
  for (let i = 0; i < refs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = refs.slice(i, i + BATCH_SIZE);
    chunk.forEach((ref) => batch.delete(ref));
    await batch.commit();
    console.log('  Deleted', Math.min(i + BATCH_SIZE, refs.length), 'of', refs.length);
  }
  console.log('Done. Deleted', count, 'userBooks.');
  if (STATUS === 'Read') {
    await syncTotalBooksReadFromShelf(uid);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
