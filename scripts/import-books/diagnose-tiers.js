/**
 * READ-ONLY diagnostic. Inspects userBooks + posts to understand the
 * rating vs tier state. Writes nothing.
 *
 * Run:
 *   cd scripts/import-books && node diagnose-tiers.js
 */
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const serviceAccount = JSON.parse(readFileSync(join(__dirname, 'service-account.json'), 'utf8'));
const app = initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore(app, 'wellread');

function has(v) { return v !== null && v !== undefined && v !== ''; }

async function main() {
  // ---- userBooks ----
  const ubSnap = await db.collection('userBooks').get();
  const ubs = ubSnap.docs.map(d => ({ id: d.id, ...d.data() }));

  const byStatus = {};
  let ratedNoTier = 0, tierNoRating = 0, both = 0, neither = 0, readCount = 0;
  const ratedNoTierSamples = [];
  for (const ub of ubs) {
    const status = ub.status ?? '(none)';
    byStatus[status] = (byStatus[status] || 0) + 1;
    const r = has(ub.rating), t = has(ub.tier);
    const isRead = status === 'read' || status === 'Read';
    if (isRead) readCount++;
    if (r && !t) { ratedNoTier++; if (ratedNoTierSamples.length < 25) ratedNoTierSamples.push(ub); }
    else if (!r && t) tierNoRating++;
    else if (r && t) both++;
    else neither++;
  }

  console.log('===== userBooks:', ubs.length, 'total =====');
  console.log('status breakdown:', byStatus);
  console.log('read count:', readCount);
  console.log('rating & NO tier :', ratedNoTier, '  <-- candidates to backfill');
  console.log('tier & NO rating :', tierNoRating);
  console.log('both rating+tier :', both);
  console.log('neither          :', neither);

  // distribution of ratings among the rated-no-tier set
  const dist = {};
  for (const ub of ubs) {
    if (has(ub.rating) && !has(ub.tier)) {
      const key = Number(ub.rating).toFixed(1);
      dist[key] = (dist[key] || 0) + 1;
    }
  }
  console.log('\nrating distribution for rated-but-untiered:');
  console.log(Object.fromEntries(Object.entries(dist).sort((a,b)=>Number(b[0])-Number(a[0]))));

  console.log('\nsamples (rated, no tier):');
  for (const ub of ratedNoTierSamples) {
    console.log(`  user=${ub.userId?.slice(0,8)} book=${ub.bookId} rating=${ub.rating} tier=${ub.tier ?? '-'} title=${ub.book?.title ?? '?'}`);
  }

  // per-user summary
  const perUser = {};
  for (const ub of ubs) {
    const u = ub.userId ?? '(none)';
    perUser[u] = perUser[u] || { ratedNoTier: 0, tierNoRating: 0, both: 0 };
    const r = has(ub.rating), t = has(ub.tier);
    if (r && !t) perUser[u].ratedNoTier++;
    else if (!r && t) perUser[u].tierNoRating++;
    else if (r && t) perUser[u].both++;
  }
  console.log('\nper-user (only users with rated-no-tier > 0):');
  for (const [u, c] of Object.entries(perUser)) {
    if (c.ratedNoTier > 0) console.log(`  ${u.slice(0,10)}: ratedNoTier=${c.ratedNoTier} tierNoRating=${c.tierNoRating} both=${c.both}`);
  }

  // ---- posts ----
  const postSnap = await db.collection('posts').get();
  const posts = postSnap.docs.map(d => ({ id: d.id, ...d.data() }));
  let pRatedNoTier = 0, pTierNoRating = 0, pBoth = 0, pNeither = 0;
  for (const p of posts) {
    const r = has(p.rating), t = has(p.tier);
    if (r && !t) pRatedNoTier++;
    else if (!r && t) pTierNoRating++;
    else if (r && t) pBoth++;
    else pNeither++;
  }
  console.log('\n===== posts:', posts.length, 'total =====');
  console.log('rating & NO tier :', pRatedNoTier);
  console.log('tier & NO rating :', pTierNoRating);
  console.log('both             :', pBoth);
  console.log('neither          :', pNeither);

  // Try to find Andrew's uid by display name
  const userSnap = await db.collection('users').get();
  const andrews = userSnap.docs.map(d => ({ id: d.id, ...d.data() }))
    .filter(u => JSON.stringify(u).toLowerCase().includes('andrew'));
  console.log('\npossible Andrew users:');
  for (const a of andrews) console.log(`  uid=${a.id} name=${a.displayName ?? a.name ?? a.username ?? '?'}`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
