/**
 * Diagnostic: dump everything we know about one SPINE member.
 *
 * Resolves a handle (with or without the leading @) through `handleClaims/{handle}`,
 * falling back to a `users.username` query for accounts created before that
 * collection existed, then prints the profile doc, library breakdown, tier list,
 * recent posts, social graph, notifications and any Book Blends.
 *
 * Prerequisites: same as import.js (scripts/import-books/service-account.json).
 *
 * Run:
 *   cd scripts/import-books
 *   node inspect-user.js @jennierubyjane
 *   node inspect-user.js jennierubyjane --posts 25 --json
 *   node inspect-user.js --uid abc123XYZ
 */

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---- args -------------------------------------------------------------------

const argv = process.argv.slice(2);
let handleArg = null;
let uidArg = null;
let postLimit = 10;
let asJson = false;

for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--uid') uidArg = argv[++i];
  else if (a === '--posts') postLimit = parseInt(argv[++i], 10) || 10;
  else if (a === '--json') asJson = true;
  else if (!a.startsWith('-')) handleArg = a;
}

if (!handleArg && !uidArg) {
  console.error('Usage: node inspect-user.js <@handle> [--posts N] [--json]');
  console.error('       node inspect-user.js --uid <firebaseAuthUid> [--posts N] [--json]');
  process.exit(1);
}

const handle = handleArg ? handleArg.replace(/^@/, '').trim().toLowerCase() : null;

// ---- firestore --------------------------------------------------------------

const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS || join(__dirname, 'service-account.json');

let serviceAccount;
try {
  serviceAccount = JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
} catch {
  console.error('Missing or invalid service account JSON at', SERVICE_ACCOUNT_PATH);
  console.error('Firebase Console → Project Settings → Service Accounts → Generate new private key.');
  process.exit(1);
}

const app = initializeApp({ credential: cert(serviceAccount) });
const db = getFirestore(app, 'wellread');

// ---- helpers ----------------------------------------------------------------

const ts = (v) => {
  if (!v) return null;
  if (typeof v.toDate === 'function') return v.toDate().toISOString();
  if (v instanceof Date) return v.toISOString();
  return String(v);
};

const short = (s, n = 120) =>
  !s ? '' : (s.length > n ? s.slice(0, n - 1) + '…' : s).replace(/\s+/g, ' ');

function line(label, value) {
  if (value === null || value === undefined || value === '') return;
  console.log(`  ${label.padEnd(22)} ${value}`);
}

/** handleClaims/{handle} → uid, with a users.username fallback for legacy accounts. */
async function resolveUid() {
  if (uidArg) return { uid: uidArg, via: '--uid' };

  const claim = await db.collection('handleClaims').doc(handle).get();
  if (claim.exists && claim.data().uid) {
    return { uid: claim.data().uid, via: `handleClaims/${handle}` };
  }

  // Legacy: no claim doc. Try the stored username, case-insensitively.
  for (const value of [handle, handleArg.replace(/^@/, '')]) {
    const snap = await db.collection('users').where('username', '==', value).limit(5).get();
    if (!snap.empty) {
      if (snap.size > 1) {
        console.log(`Note: ${snap.size} users share username "${value}". Using the first; the rest:`);
        snap.docs.slice(1).forEach((d) => console.log(`  ${d.id}  ${d.data().displayName || ''}`));
      }
      return { uid: snap.docs[0].id, via: `users.username == "${value}"` };
    }
  }
  return null;
}

// ---- main -------------------------------------------------------------------

async function main() {
  const resolved = await resolveUid();
  if (!resolved) {
    console.error(`No member found for @${handle}.`);
    console.error('The handle may be free, spelled differently, or claimed on a different database.');
    process.exit(2);
  }
  const { uid, via } = resolved;

  const userSnap = await db.collection('users').doc(uid).get();
  if (!userSnap.exists) {
    console.error(`handleClaims points at uid ${uid} but users/${uid} does not exist (orphaned claim).`);
    process.exit(2);
  }
  const u = userSnap.data();

  // Library, posts, social graph, notifications, blends.
  const [booksSnap, postsSnap, followersSnap, notifSnap, blendsSnap] = await Promise.all([
    db.collection('userBooks').where('userId', '==', uid).get(),
    db.collection('posts').where('userId', '==', uid).orderBy('createdAt', 'desc').limit(postLimit).get(),
    db.collection('users').where('following', 'array-contains', uid).get(),
    db.collection('users').doc(uid).collection('notifications').get(),
    db.collection('bookBlends').where('userIds', 'array-contains', uid).get(),
  ]);

  const rows = booksSnap.docs.map((d) => d.data());
  const byStatus = rows.reduce((acc, r) => {
    const k = r.status || 'unknown';
    acc[k] = (acc[k] || 0) + 1;
    return acc;
  }, {});
  const tiers = rows.reduce((acc, r) => {
    if (r.tier) acc[r.tier] = (acc[r.tier] || 0) + 1;
    return acc;
  }, {});
  const rated = rows.filter((r) => typeof r.rating === 'number');
  const avgRating = rated.length
    ? (rated.reduce((s, r) => s + r.rating, 0) / rated.length).toFixed(2)
    : null;

  // Hydrate titles for the most recent library activity and the listed posts.
  const bookIds = [
    ...new Set([
      ...rows
        .slice()
        .sort((a, b) => (ts(b.updatedAt) || '').localeCompare(ts(a.updatedAt) || ''))
        .slice(0, 10)
        .map((r) => r.bookId),
      ...postsSnap.docs.map((d) => d.data().bookId),
    ]),
  ].filter(Boolean);

  const books = {};
  for (let i = 0; i < bookIds.length; i += 30) {
    const chunk = bookIds.slice(i, i + 30);
    const snaps = await db.getAll(...chunk.map((id) => db.collection('books').doc(id)));
    snaps.forEach((s) => {
      if (s.exists) books[s.id] = s.data();
    });
  }
  const titleOf = (id) => (books[id] ? `${books[id].title} — ${books[id].author || '?'}` : id || '(no book)');

  const blends = blendsSnap.docs;

  if (asJson) {
    console.log(
      JSON.stringify(
        {
          resolvedVia: via,
          uid,
          user: { ...u, joinedAt: ts(u.joinedAt) },
          library: { total: rows.length, byStatus, tiers, ratedCount: rated.length, avgRating },
          following: u.following || [],
          followers: followersSnap.docs.map((d) => d.id),
          notificationCount: notifSnap.size,
          blends: blends.map((d) => ({ id: d.id, ...d.data() })),
          posts: postsSnap.docs.map((d) => {
            const p = d.data();
            return { id: d.id, ...p, createdAt: ts(p.createdAt), dateFinished: ts(p.dateFinished), book: titleOf(p.bookId) };
          }),
          recentLibrary: rows
            .slice()
            .sort((a, b) => (ts(b.updatedAt) || '').localeCompare(ts(a.updatedAt) || ''))
            .slice(0, 10)
            .map((r) => ({ book: titleOf(r.bookId), status: r.status, tier: r.tier, rating: r.rating, updatedAt: ts(r.updatedAt) })),
        },
        null,
        2
      )
    );
    return;
  }

  console.log(`\n@${u.username || handle}  (resolved via ${via})`);
  console.log('='.repeat(60));

  console.log('\nPROFILE');
  line('uid', uid);
  line('display name', u.displayName);
  line('real name', [u.firstName, u.lastName].filter(Boolean).join(' '));
  line('bio', short(u.bio, 200));
  line('joined', ts(u.joinedAt));
  line('OG-eligible', String(!u.ogIneligible));
  line('setup completed', String(!!u.profileSetupCompleted));
  line('profile photo', u.profileImageURL ? 'yes' : 'no (monogram avatar)');
  line('phone on file', u.phoneNumber ? 'yes' : 'no');
  line('test account', String(!!u.isTestAccount));
  line('reading goal', u.readingGoal);
  line('totals (self-reported)', `${u.totalBooksRead ?? 0} books / ${u.totalPagesRead ?? 0} pages`);
  line('interest tags', (u.readingInterestTags || []).join(', '));
  line('discover criteria', u.discoverCriteria ? JSON.stringify(u.discoverCriteria) : undefined);

  console.log('\nLIBRARY');
  line('userBooks rows', rows.length);
  Object.entries(byStatus).forEach(([k, v]) => line(`  ${k}`, v));
  line('tiered', Object.entries(tiers).map(([t, c]) => `${t}:${c}`).join(' ') || 'none');
  line('ratings', rated.length ? `${rated.length} rated, avg ${avgRating}/10` : 'none');

  console.log('\nRECENT LIBRARY ACTIVITY');
  rows
    .slice()
    .sort((a, b) => (ts(b.updatedAt) || '').localeCompare(ts(a.updatedAt) || ''))
    .slice(0, 10)
    .forEach((r) => {
      const bits = [r.status, r.tier ? `tier ${r.tier}` : null, r.rating ? `${r.rating}/10` : null]
        .filter(Boolean)
        .join(', ');
      console.log(`  ${(ts(r.updatedAt) || '').slice(0, 10)}  ${titleOf(r.bookId)}  [${bits}]`);
    });

  console.log('\nSOCIAL');
  line('following', (u.following || []).length);
  line('followers', followersSnap.size);
  line('notifications', notifSnap.size);
  line('book blends', blends.length ? blends.map((d) => `${d.id} (${d.data().status || 'n/a'})`).join(', ') : 'none');

  console.log(`\nPOSTS (latest ${postsSnap.size})`);
  if (postsSnap.empty) console.log('  none');
  postsSnap.docs.forEach((d) => {
    const p = d.data();
    console.log(`  ${(ts(p.createdAt) || '').slice(0, 10)}  ${p.type}  ${titleOf(p.bookId)}`);
    const meta = [p.tier ? `tier ${p.tier}` : null, p.rating ? `${p.rating}/10` : null, `${p.likeCount || 0} likes`, `${p.commentCount || 0} comments`]
      .filter(Boolean)
      .join(' · ');
    console.log(`      ${meta}`);
    if (p.caption) console.log(`      "${short(p.caption, 160)}"`);
  });
  console.log('');
}

main().then(
  () => process.exit(0),
  (e) => {
    console.error('Failed:', e.message);
    process.exit(1);
  }
);
