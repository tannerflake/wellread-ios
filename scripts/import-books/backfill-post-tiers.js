/**
 * Backfill `posts.tier` from the post author's own `userBooks.tier`.
 *
 * Problem: a book the author dragged into a tier has that tier stored on their
 * userBooks row, but the corresponding feed post's `tier` field was never set.
 * The feed only falls back to a local tier for the *current* user's own posts,
 * so everyone else sees no tier badge on that post. This copies the author's
 * real tier onto the post so it renders for all viewers.
 *
 * Only posts with NO existing tier are touched. Posts whose author has no tier
 * for that book are skipped (never invents a tier from a rating).
 *
 * Dry-run (default, writes nothing):
 *   cd scripts/import-books && node backfill-post-tiers.js
 * Apply:
 *   cd scripts/import-books && node backfill-post-tiers.js --apply
 */
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const APPLY = process.argv.includes('--apply');
const __dirname = dirname(fileURLToPath(import.meta.url));
const serviceAccount = JSON.parse(readFileSync(join(__dirname, 'service-account.json'), 'utf8'));
const app = initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore(app, 'wellread');

const has = v => v !== null && v !== undefined && v !== '';

async function main() {
  console.log(APPLY ? '*** APPLY MODE — will write to Firestore ***\n' : '--- DRY RUN (no writes) — pass --apply to commit ---\n');

  // Index every user's tiered books: key `${userId}::${bookId}` -> tier
  const ubSnap = await db.collection('userBooks').get();
  const tierByUserBook = new Map();
  for (const d of ubSnap.docs) {
    const ub = d.data();
    if (has(ub.userId) && has(ub.bookId) && has(ub.tier)) {
      tierByUserBook.set(`${ub.userId}::${ub.bookId}`, ub.tier);
    }
  }
  console.log(`Indexed ${tierByUserBook.size} tiered userBooks.\n`);

  const postSnap = await db.collection('posts').get();
  const toUpdate = [];
  let alreadyTiered = 0, noAuthorTier = 0, missingBookId = 0;

  for (const d of postSnap.docs) {
    const p = d.data();
    if (has(p.tier)) { alreadyTiered++; continue; }
    if (!has(p.bookId)) { missingBookId++; continue; }
    const tier = tierByUserBook.get(`${p.userId}::${p.bookId}`);
    if (!tier) { noAuthorTier++; continue; }
    toUpdate.push({ ref: d.ref, id: d.id, userId: p.userId, bookId: p.bookId, tier, title: p.book?.title ?? '?' });
  }

  console.log(`posts total          : ${postSnap.size}`);
  console.log(`already have a tier   : ${alreadyTiered}`);
  console.log(`no bookId (skipped)   : ${missingBookId}`);
  console.log(`author has no tier    : ${noAuthorTier}  (left as-is — never invented)`);
  console.log(`WILL BACKFILL         : ${toUpdate.length}\n`);

  for (const u of toUpdate) {
    console.log(`  post=${u.id.slice(0,8)} user=${u.userId.slice(0,8)} book=${u.bookId} -> tier=${u.tier}  (${u.title})`);
  }

  if (!APPLY) { console.log('\nDry run complete. Re-run with --apply to write these tiers.'); return; }

  console.log('\nWriting...');
  let n = 0;
  for (const u of toUpdate) {
    await u.ref.update({ tier: u.tier });
    n++;
  }
  console.log(`Done. Updated ${n} posts.`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
