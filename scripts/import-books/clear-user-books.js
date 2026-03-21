/**
 * Delete all userBooks for a given Firebase user (wellread database).
 *
 * Prerequisites:
 *   Firebase service account key at scripts/import-books/service-account.json
 *   (same as import.js - Firebase Console → Project Settings → Service Accounts → Generate new private key)
 *
 * Run:
 *   cd scripts/import-books
 *   FIREBASE_UID="jCaSGxcYgHZd6OzXfxmGNn1GZBj2" node clear-user-books.js
 *
 * Optional: GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 */

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));

const FIREBASE_UID = process.env.FIREBASE_UID;
const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_APPLICATION_CREDENTIALS || join(__dirname, 'service-account.json');

if (!FIREBASE_UID) {
  console.error('Set FIREBASE_UID (the user whose books to clear). Example: FIREBASE_UID="jCaSGxcYgHZd6OzXfxmGNn1GZBj2" node clear-user-books.js');
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

async function main() {
  const col = db.collection('userBooks');
  const snapshot = await col.where('userId', '==', FIREBASE_UID).get();
  const count = snapshot.size;
  if (count === 0) {
    console.log('No userBooks found for', FIREBASE_UID);
    return;
  }
  console.log('Deleting', count, 'userBooks for user', FIREBASE_UID);
  const refs = snapshot.docs.map((d) => d.ref);
  for (let i = 0; i < refs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = refs.slice(i, i + BATCH_SIZE);
    chunk.forEach((ref) => batch.delete(ref));
    await batch.commit();
    console.log('  Deleted', Math.min(i + BATCH_SIZE, refs.length), 'of', refs.length);
  }
  console.log('Done. Deleted', count, 'userBooks.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
