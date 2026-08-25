/**
 * Backfill `bookStats/` — the community-popularity aggregate behind search
 * ranking (how many distinct members have shelved each work).
 *
 * Reads every userBooks row, resolves each bookId to its books/ doc, groups by
 * popularityKey (normalized main title + primary author surname — MUST match
 * functions/src/index.ts `popularityKey` and Swift `BookSearchRanker.popularityKey`),
 * and writes one bookStats doc per work. Test accounts (users.isTestAccount)
 * are excluded. Safe to re-run: docs are fully overwritten by key.
 *
 * Prerequisites: same as import.js (scripts/import-books/service-account.json).
 *
 * Run:
 *   cd scripts/import-books
 *   node backfill-book-stats.js            # dry run (prints what it would write)
 *   node backfill-book-stats.js --write    # actually write
 */

import { createHash } from 'crypto';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const WRITE = process.argv.includes('--write');

const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS || join(__dirname, 'service-account.json');

let serviceAccount;
try {
  serviceAccount = JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
} catch {
  console.error('Missing or invalid service account JSON at', SERVICE_ACCOUNT_PATH);
  process.exit(1);
}

const app = initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore(app, 'wellread');

// Keep in lockstep with functions/src/index.ts popularityKey.
function popularityKey(title, author) {
  const normalize = (s) =>
    s
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .toLowerCase()
      .replace(/['’]/g, '')
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  let raw = title.replace(/\([^)]*\)|\[[^\]]*\]/g, ' ');
  raw = raw.split(':')[0] ?? raw;
  let t = normalize(raw);
  for (const article of ['the ', 'a ', 'an ']) {
    if (t.startsWith(article)) {
      t = t.slice(article.length);
      break;
    }
  }
  if (!t) return '';
  const primary = normalize(author.split(',')[0] ?? '');
  const surname = primary.split(' ').filter(Boolean).pop() ?? '';
  return `${t}|${surname}`;
}

async function main() {
  // Test accounts never count toward popularity.
  const usersSnap = await db.collection('users').select('isTestAccount').get();
  const testUids = new Set(
    usersSnap.docs.filter((d) => d.data().isTestAccount === true).map((d) => d.id)
  );
  console.log(`users: ${usersSnap.size} (${testUids.size} test accounts excluded)`);

  const ubSnap = await db.collection('userBooks').select('userId', 'bookId').get();
  console.log(`userBooks rows: ${ubSnap.size}`);

  // bookId -> set of real users who shelved it
  const usersByBookId = new Map();
  for (const doc of ubSnap.docs) {
    const { userId, bookId } = doc.data();
    if (!userId || !bookId || testUids.has(userId)) continue;
    if (!usersByBookId.has(bookId)) usersByBookId.set(bookId, new Set());
    usersByBookId.get(bookId).add(userId);
  }
  console.log(`distinct bookIds: ${usersByBookId.size}`);

  // Resolve books in chunks of 300 via getAll.
  const bookIds = [...usersByBookId.keys()];
  const bookMeta = new Map(); // bookId -> {title, author}
  for (let i = 0; i < bookIds.length; i += 300) {
    const refs = bookIds.slice(i, i + 300).map((id) => db.collection('books').doc(id));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (!s.exists) continue;
      const d = s.data();
      bookMeta.set(s.id, {
        title: (d.title ?? '').trim(),
        author: (d.author ?? '').trim(),
      });
    }
  }
  console.log(`resolved books: ${bookMeta.size}`);

  // key -> {userIds, sampleTitle, sampleAuthor}
  const stats = new Map();
  for (const [bookId, uids] of usersByBookId) {
    const meta = bookMeta.get(bookId);
    if (!meta) continue;
    const key = popularityKey(meta.title, meta.author);
    if (!key) continue;
    if (!stats.has(key)) {
      stats.set(key, { userIds: new Set(), sampleTitle: meta.title, sampleAuthor: meta.author });
    }
    const entry = stats.get(key);
    for (const u of uids) entry.userIds.add(u);
  }

  const popular = [...stats.entries()].filter(([, v]) => v.userIds.size >= 2);
  console.log(`works: ${stats.size}; with 2+ members: ${popular.length}`);
  for (const [key, v] of popular.sort((a, b) => b[1].userIds.size - a[1].userIds.size).slice(0, 20)) {
    console.log(`  ${String(v.userIds.size).padStart(3)}  ${v.sampleTitle} — ${v.sampleAuthor}  [${key}]`);
  }

  if (!WRITE) {
    console.log('\nDry run — re-run with --write to persist.');
    return;
  }

  let batch = db.batch();
  let inBatch = 0;
  let written = 0;
  for (const [key, v] of stats) {
    const docId = createHash('sha256').update(key).digest('hex').slice(0, 40);
    batch.set(db.collection('bookStats').doc(docId), {
      key,
      sampleTitle: v.sampleTitle,
      sampleAuthor: v.sampleAuthor,
      userIds: [...v.userIds],
      count: v.userIds.size,
      updatedAt: FieldValue.serverTimestamp(),
    });
    inBatch += 1;
    written += 1;
    if (inBatch === 400) {
      await batch.commit();
      batch = db.batch();
      inBatch = 0;
    }
  }
  if (inBatch > 0) await batch.commit();
  console.log(`wrote ${written} bookStats docs.`);
}

main().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
