import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { DocumentData, Firestore } from "firebase-admin/firestore";

const app = getApps().length ? getApps()[0]! : initializeApp();
const db: Firestore = getFirestore(app, "wellread");
const messaging = getMessaging(app);

const DATABASE_ID = "wellread";

function firstNameFromUser(data: DocumentData | undefined): string {
  if (!data) return "Someone";
  const fn = (data.firstName as string | undefined)?.trim();
  if (fn && fn.length > 0) return fn;
  const dn = (data.displayName as string | undefined)?.trim() ?? "";
  if (dn.length === 0) return "Someone";
  return dn.split(/\s+/)[0] ?? "Someone";
}

function formatRating(r: unknown): string {
  if (typeof r === "number" && Number.isFinite(r)) return r.toFixed(1);
  if (typeof r === "string") {
    const n = parseFloat(r);
    if (Number.isFinite(n)) return n.toFixed(1);
  }
  return "?";
}

/** First ~8 words; ellipsis if more remains in source. */
function teaser8Words(text: string): string {
  const t = text.trim().replace(/\s+/g, " ");
  if (!t) return "";
  const words = t.split(/\s+/);
  const head = words.slice(0, 8).join(" ");
  if (words.length <= 8) return head;
  return `${head}...`;
}

async function bookTitle(bookId: string | undefined): Promise<string | null> {
  if (!bookId) return null;
  const snap = await db.collection("books").doc(bookId).get();
  const t = snap.data()?.title as string | undefined;
  return t?.trim() || null;
}

async function tokensForUser(uid: string): Promise<string[]> {
  const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();
  return snap.docs.map((d) => d.data().token as string).filter((t): t is string => typeof t === "string" && t.length > 0);
}

async function sendToUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<void> {
  const tokens = await tokensForUser(uid);
  if (!tokens.length) return;
  const messages = tokens.map((token) => ({
    token,
    notification: { title, body },
    data,
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  }));
  await messaging.sendEach(messages);
}

/** Fixed post id for diagnostics-only pushes (deep link may not resolve to a real post). */
const TEST_PUSH_POST_ID = "00000000-0000-4000-8000-000000000001";

const TEST_PUSH_TYPES = new Set([
  "friend_review_posted",
  "review_liked",
  "review_commented",
  "thread_commented",
]);

/**
 * Authenticated clients only: sends one sample notification of the given type to the caller’s uid
 * using stored FCM tokens (same path as production `sendToUser`).
 */
export const sendTestPushNotification = onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const raw = request.data as { type?: string } | undefined;
    const type = raw?.type;
    if (!type || !TEST_PUSH_TYPES.has(type)) {
      throw new HttpsError(
        "invalid-argument",
        "type must be one of: friend_review_posted, review_liked, review_commented, thread_commented"
      );
    }

    const tokens = await tokensForUser(uid);
    if (!tokens.length) {
      throw new HttpsError(
        "failed-precondition",
        "No FCM tokens stored for this user. Use a physical device, allow notifications, and wait for the Firestore write."
      );
    }

    switch (type) {
      case "friend_review_posted":
        await sendToUser(
          uid,
          "Alex gave Sample Book a 9.0",
          "Smart, ambitious, provocative, and way more readable than...",
          { type: "friend_review_posted", postId: TEST_PUSH_POST_ID }
        );
        break;
      case "review_liked":
        await sendToUser(uid, "Alex liked your review of Sample Book", "", {
          type: "review_liked",
          postId: TEST_PUSH_POST_ID,
        });
        break;
      case "review_commented":
        await sendToUser(
          uid,
          "Alex commented on your review of Sample Book",
          "Great take on chapter three...",
          { type: "review_commented", postId: TEST_PUSH_POST_ID }
        );
        break;
      case "thread_commented":
        await sendToUser(
          uid,
          "Alex also commented on the Sample Book review you joined",
          "Adding my two cents here...",
          { type: "thread_commented", postId: TEST_PUSH_POST_ID }
        );
        break;
      default:
        throw new HttpsError("invalid-argument", "Unknown type");
    }

    return { ok: true, sent: tokens.length, type };
  }
);

/** Friends who follow `authorUid` (Firestore `following` contains author string ids). */
async function recipientUidsWhoFollow(authorUid: string): Promise<string[]> {
  const q = await db.collection("users").where("following", "array-contains", authorUid).get();
  return q.docs.map((d) => d.id).filter((id) => id !== authorUid);
}

export const onFriendReviewPosted = onDocumentCreated(
  {
    document: "posts/{postId}",
    database: DATABASE_ID,
  },
  async (event) => {
    const postId = event.params.postId as string;
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "finishedBook") return;
    const authorId = data.userId as string;
    if (!authorId) return;

    const author = (await db.collection("users").doc(authorId).get()).data();
    const first = firstNameFromUser(author);
    const book = await bookTitle(data.bookId as string | undefined);
    const bookPart = book ?? "a book";
    const rating = formatRating(data.rating);
    const caption = (data.caption as string | undefined)?.trim() ?? "";
    const teaser = teaser8Words(caption);
    const titleLine = `${first} gave ${bookPart} a ${rating}`;

    const title = titleLine;
    const body = teaser ? teaser : "Open Spynes to read the full review.";

    const recipients = await recipientUidsWhoFollow(authorId);
    const payload = {
      type: "friend_review_posted",
      postId,
    };
    for (const uid of recipients) {
      await sendToUser(uid, title, body, payload);
    }
  }
);

export const onPostLiked = onDocumentCreated(
  {
    document: "postLikes/{likeId}",
    database: DATABASE_ID,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const d = snap.data();
    const likerId = d.userId as string;
    const postId = d.postId as string;
    if (!likerId || !postId) return;

    const post = await db.collection("posts").doc(postId).get();
    const postData = post.data();
    if (!postData) return;
    const authorId = postData.userId as string;
    if (!authorId || likerId === authorId) return;

    const liker = (await db.collection("users").doc(likerId).get()).data();
    const first = firstNameFromUser(liker);
    const book = await bookTitle(postData.bookId as string | undefined);
    const title = book
      ? `${first} liked your review of ${book}`
      : `${first} liked your review`;

    await sendToUser(authorId, title, "", {
      type: "review_liked",
      postId,
    });
  }
);

export const onCommentCreated = onDocumentCreated(
  {
    document: "comments/{commentId}",
    database: DATABASE_ID,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const d = snap.data();
    const commenterId = d.userId as string;
    const postId = d.postId as string;
    const commentText = (d.text as string | undefined)?.trim() ?? "";
    if (!commenterId || !postId) return;

    const post = await db.collection("posts").doc(postId).get();
    const postData = post.data();
    if (!postData) return;
    const authorId = postData.userId as string;
    if (!authorId) return;

    const commenter = (await db.collection("users").doc(commenterId).get()).data();
    const first = firstNameFromUser(commenter);
    const book = await bookTitle(postData.bookId as string | undefined);

    // Author: review_commented (not if self-comment)
    if (commenterId !== authorId) {
      const title = book
        ? `${first} commented on your review of ${book}`
        : `${first} replied to your review`;
      const preview = teaser8Words(commentText);
      const body = preview.length > 0 ? preview : "";
      await sendToUser(authorId, title, body, {
        type: "review_commented",
        postId,
      });
    }

    // Thread participants (exclude new commenter and post author — author already notified above)
    const commentsSnap = await db.collection("comments").where("postId", "==", postId).get();
    const participantIds = new Set<string>();
    commentsSnap.forEach((doc) => {
      const uid = doc.data().userId as string | undefined;
      if (uid) participantIds.add(uid);
    });
    participantIds.delete(commenterId);
    participantIds.delete(authorId);

    const threadTitle = book
      ? `${first} also commented on the ${book} review you joined`
      : `${first} replied in a review thread you joined`;
    const threadBody = teaser8Words(commentText);

    for (const uid of participantIds) {
      await sendToUser(uid, threadTitle, threadBody, {
        type: "thread_commented",
        postId,
      });
    }
  }
);
