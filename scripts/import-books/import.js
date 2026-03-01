/**
 * One-time script: import books from books.json into Firestore (wellread database)
 * under the given user. Resolves each ISBN via Google Books API, then creates
 * book + userBook (status Read, rating 1-10).
 *
 * Prerequisites:
 *   1. Firebase service account key: Firebase Console → Project Settings → Service Accounts
 *      → Generate new private key. Save as scripts/import-books/service-account.json (gitignored).
 *   2. Google Books API key (for ISBN lookup). Same key as in the app, or create one.
 *   3. Your Firebase Auth UID (Firebase Console → Authentication → Users → your user → UID).
 *
 * Run:
 *   cd scripts/import-books
 *   npm install
 *   FIREBASE_UID="your-uid" GOOGLE_BOOKS_API_KEY="your-key" node import.js
 */

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));

const FIREBASE_UID = process.env.FIREBASE_UID;
const GOOGLE_BOOKS_API_KEY = process.env.GOOGLE_BOOKS_API_KEY;
const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_APPLICATION_CREDENTIALS || join(__dirname, 'service-account.json');

if (!FIREBASE_UID) {
  console.error('Set FIREBASE_UID (your Firebase Auth user ID). Get it from Firebase Console → Authentication → Users.');
  process.exit(1);
}
if (!GOOGLE_BOOKS_API_KEY) {
  console.error('Set GOOGLE_BOOKS_API_KEY (for Google Books API ISBN lookup).');
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

const booksPath = join(__dirname, 'books.json');
const books = JSON.parse(readFileSync(booksPath, 'utf8'));

function pickBestImage(links) {
  if (!links) return '';
  const url = links.extraLarge || links.large || links.medium || links.small || links.thumbnail || links.smallThumbnail || '';
  return url.replace(/^http:\/\//, 'https://');
}

async function fetchBookByIsbn(isbn) {
  const url = `https://www.googleapis.com/books/v1/volumes?q=isbn:${isbn}&maxResults=1&key=${GOOGLE_BOOKS_API_KEY}`;
  const res = await fetch(url);
  const data = await res.json();
  const item = data.items?.[0];
  if (!item?.volumeInfo) return null;
  const vi = item.volumeInfo;
  const coverURL = pickBestImage(vi.imageLinks);
  return {
    id: item.id,
    title: vi.title || 'Unknown',
    author: (vi.authors && vi.authors.length) ? vi.authors.join(', ') : 'Unknown',
    coverURL: coverURL || '',
    pageCount: vi.pageCount ?? null,
    publishedDate: null,
    description: vi.description ?? null,
    genres: vi.categories ?? [],
  };
}

async function ensureBook(book) {
  const ref = db.collection('books').doc(book.id);
  const snap = await ref.get();
  if (snap.exists) return;
  await ref.set({
    title: book.title,
    author: book.author,
    coverURL: book.coverURL,
    pageCount: book.pageCount,
    publishedDate: book.publishedDate,
    description: book.description,
    genres: book.genres,
  });
}

async function addUserBook(book, rating) {
  const id = crypto.randomUUID();
  const now = new Date();
  await db.collection('userBooks').doc(id).set({
    userId: FIREBASE_UID,
    bookId: book.id,
    status: 'Read',
    rating: Math.round(rating),
    reviewText: null,
    dateStarted: null,
    dateFinished: Timestamp.fromDate(now),
    createdAt: Timestamp.fromDate(now),
    updatedAt: Timestamp.fromDate(now),
    recommendedTo: [],
    tier: null,
  });
}

async function main() {
  console.log('Importing', books.length, 'books for Firebase UID', FIREBASE_UID);
  let ok = 0, fail = 0;
  for (const row of books) {
    try {
      let book = await fetchBookByIsbn(row.isbn);
      if (!book) {
        book = {
          id: `isbn-${row.isbn}`,
          title: row.title,
          author: row.author,
          coverURL: '',
          pageCount: null,
          publishedDate: null,
          description: null,
          genres: [],
        };
      }
      await ensureBook(book);
      await addUserBook(book, row.rating);
      console.log('  ✓', book.title);
      ok++;
    } catch (e) {
      console.error('  ✗', row.title, e.message);
      fail++;
    }
  }
  console.log('Done.', ok, 'imported,', fail, 'failed.');
}

main().catch((e) => { console.error(e); process.exit(1); });
