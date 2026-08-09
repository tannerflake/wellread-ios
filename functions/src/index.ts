import { initializeApp, getApps } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { onDocumentCreated, onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
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

/** Null when the post has no usable rating (e.g. marked read without ranking). */
function formatRating(r: unknown): string | null {
  if (typeof r === "number" && Number.isFinite(r)) return r.toFixed(1);
  if (typeof r === "string") {
    const n = parseFloat(r);
    if (Number.isFinite(n)) return n.toFixed(1);
  }
  return null;
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

/** APNs attachments require https; Google Books covers are often stored as http. */
function httpsUpgraded(url: string | null): string | null {
  if (!url) return null;
  if (url.startsWith("https://")) return url;
  if (url.startsWith("http://")) return `https://${url.slice("http://".length)}`;
  return null;
}

async function bookInfo(
  bookId: string | undefined
): Promise<{ title: string | null; coverURL: string | null }> {
  if (!bookId) return { title: null, coverURL: null };
  const snap = await db.collection("books").doc(bookId).get();
  const data = snap.data();
  const title = (data?.title as string | undefined)?.trim() || null;
  const coverURL = httpsUpgraded((data?.coverURL as string | undefined)?.trim() || null);
  return { title, coverURL };
}

async function tokensForUser(uid: string): Promise<string[]> {
  const snap = await db.collection("users").doc(uid).collection("fcmTokens").get();
  return snap.docs.map((d) => d.data().token as string).filter((t): t is string => typeof t === "string" && t.length > 0);
}

/**
 * Data-only background push (no alert, no sound) — wakes the app so it can
 * react, e.g. clearing a withdrawn blend invite from Notification Center.
 */
async function sendSilentToUser(uid: string, data: Record<string, string>): Promise<void> {
  const tokens = await tokensForUser(uid);
  if (!tokens.length) return;
  const messages = tokens.map((token) => ({
    token,
    data,
    apns: {
      headers: {
        "apns-push-type": "background",
        "apns-priority": "5",
      },
      payload: { aps: { "content-available": 1 } },
    },
  }));
  const resp = await messaging.sendEach(messages);
  logger.info("push sendSilentToUser", { uid, type: data.type, tokenCount: tokens.length, successCount: resp.successCount, failureCount: resp.failureCount });
}

async function sendToUser(
  uid: string,
  title: string,
  body: string,
  data: Record<string, string>,
  imageUrl?: string | null
): Promise<void> {
  const tokens = await tokensForUser(uid);
  if (!tokens.length) {
    logger.warn("push skipped: no FCM tokens for user", { uid });
    return;
  }
  // iOS often drops or mishandles alerts with an empty body; keep a short fallback.
  const bodyText = body.trim().length > 0 ? body.trim() : "Tap to open SPINE";
  // Book covers ride along as a rich-notification image: `fcmOptions.imageUrl` puts the URL in
  // the APNs payload and `mutableContent` routes it through the app's Notification Service
  // Extension, which downloads and attaches the thumbnail. `coverImageURL` in data is the
  // extension's fallback key.
  const dataPayload = imageUrl ? { ...data, coverImageURL: imageUrl } : data;
  const messages = tokens.map((token) => ({
    token,
    notification: { title, body: bodyText },
    data: dataPayload,
    apns: {
      payload: {
        aps: {
          alert: {
            title,
            body: bodyText,
          },
          sound: "default",
          ...(imageUrl ? { mutableContent: true } : {}),
        },
      },
      ...(imageUrl ? { fcmOptions: { imageUrl } } : {}),
    },
  }));
  const resp = await messaging.sendEach(messages);
  if (resp.failureCount > 0) {
    resp.responses.forEach((r, i) => {
      if (!r.success) {
        logger.error("FCM send failed", {
          uid,
          tokenPrefix: tokens[i]?.slice(0, 12),
          error: r.error?.message,
          code: r.error?.code,
        });
      }
    });
  }
  logger.info("push sendToUser", { uid, tokenCount: tokens.length, successCount: resp.successCount, failureCount: resp.failureCount });
}

/** Fixed post id for diagnostics-only pushes (deep link may not resolve to a real post). */
const TEST_PUSH_POST_ID = "00000000-0000-4000-8000-000000000001";

/** Stable sample cover (Sapiens) so diagnostics pushes exercise the rich-notification path. */
const TEST_PUSH_COVER_URL = "https://covers.openlibrary.org/b/isbn/9780062316097-L.jpg";

const TEST_PUSH_TYPES = new Set([
  "friend_review_posted",
  "review_liked",
  "review_commented",
  "thread_commented",
  "new_follower",
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
        "type must be one of: friend_review_posted, review_liked, review_commented, thread_commented, new_follower"
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
          { type: "friend_review_posted", postId: TEST_PUSH_POST_ID },
          TEST_PUSH_COVER_URL
        );
        break;
      case "review_liked":
        await sendToUser(
          uid,
          "Alex liked your review of Sample Book",
          "",
          { type: "review_liked", postId: TEST_PUSH_POST_ID },
          TEST_PUSH_COVER_URL
        );
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
      case "new_follower":
        // followerId is the caller so the tap deep-links to a real profile (your own).
        await sendToUser(
          uid,
          "Alex started following you",
          "See what they're reading on SPINE.",
          { type: "new_follower", followerId: uid }
        );
        break;
      default:
        throw new HttpsError("invalid-argument", "Unknown type");
    }

    return { ok: true, sent: tokens.length, type };
  }
);

// MARK: Account deletion (App Store guideline 5.1.1(v))

/** Deletes every document matched by `query` in batches; returns count deleted. */
async function deleteByQuery(
  query: FirebaseFirestore.Query,
  batchSize = 300
): Promise<number> {
  let total = 0;
  for (;;) {
    const snap = await query.limit(batchSize).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    total += snap.size;
    if (snap.size < batchSize) break;
  }
  return total;
}

/**
 * Permanently deletes the caller's account: all Firestore data they own,
 * references to them in other users' following lists, and finally the
 * Firebase Auth user. Client signs out locally after this resolves.
 */
export const deleteAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    logger.info("deleteAccount start", { uid });

    // Posts authored by the user, plus comments/likes attached to those posts.
    const postsSnap = await db.collection("posts").where("userId", "==", uid).get();
    for (const post of postsSnap.docs) {
      await deleteByQuery(db.collection("comments").where("postId", "==", post.id));
      await deleteByQuery(db.collection("postLikes").where("postId", "==", post.id));
      await post.ref.delete();
    }

    // Content the user created on other people's posts / shared state.
    await deleteByQuery(db.collection("comments").where("userId", "==", uid));
    await deleteByQuery(db.collection("postLikes").where("userId", "==", uid));
    await deleteByQuery(db.collection("userBooks").where("userId", "==", uid));
    await deleteByQuery(db.collection("recommendations").where("fromUserId", "==", uid));
    await deleteByQuery(db.collection("recommendations").where("toUserId", "==", uid));
    await deleteByQuery(db.collection("bookBlends").where("userIds", "array-contains", uid));
    await deleteByQuery(db.collection("dismissedSuggestions").where("userId", "==", uid));
    await deleteByQuery(db.collection("handleClaims").where("uid", "==", uid));

    // Remove the user from other members' following lists.
    const followersSnap = await db
      .collection("users")
      .where("following", "array-contains", uid)
      .get();
    for (const follower of followersSnap.docs) {
      await follower.ref.update({ following: FieldValue.arrayRemove(uid) });
    }

    // User doc + subcollections (fcmTokens etc.), then the Auth account itself.
    await db.recursiveDelete(db.collection("users").doc(uid));
    await getAuth(app).deleteUser(uid);

    logger.info("deleteAccount done", { uid });
    return { ok: true };
  }
);

/** Tanner's Firebase Auth uid (@tan). New accounts follow him by default (seeded client-side);
 * this side follows them back, since Firestore rules only let clients write their own doc. */
const FOUNDER_UID = "jCaSGxcYgHZd6OzXfxmGNn1GZBj2";

/** Accounts hidden app-wide except from specific viewers (mirrors `HiddenAccounts` in the iOS app).
 * Their activity must not generate pushes to anyone outside the allowlist. */
const HIDDEN_ACCOUNT_VIEWERS: Record<string, string[]> = {
  // tanner@tinyhealth.com test account (@tantest) — visible only to Tanner (tannerflake@gmail.com).
  lWfYPy4fOxdQYFUYEXAGnpvNscw2: [FOUNDER_UID],
};

/** False when `actorUid` is a hidden account and `recipientUid` isn't allowed to see it. */
function hiddenAccountCanNotify(actorUid: string, recipientUid: string): boolean {
  const allowed = HIDDEN_ACCOUNT_VIEWERS[actorUid];
  if (!allowed) return true;
  return recipientUid === actorUid || allowed.includes(recipientUid);
}

/**
 * New account created: the founder auto-follows the new member, and gets a push that
 * someone joined (the new doc is already seeded following him).
 */
export const onUserCreated = onDocumentCreated(
  {
    document: "users/{uid}",
    database: DATABASE_ID,
  },
  async (event) => {
    const uid = event.params.uid as string;
    if (!uid || uid === FOUNDER_UID) return;
    const first = firstNameFromUser(event.data?.data());
    try {
      await db.collection("users").doc(FOUNDER_UID).update({
        following: FieldValue.arrayUnion(uid),
      });
    } catch (e) {
      logger.error("founder auto-follow failed", { uid, error: (e as Error).message });
    }
    await sendToUser(
      FOUNDER_UID,
      `${first} joined SPINE`,
      "They follow you — and you now follow them back.",
      { type: "new_follower", followerId: uid }
    );
  }
);

/**
 * A user's `following` array grew: push a new-follower alert to each newly-followed user.
 * (Follows are written client-side as arrayUnion on the follower's own doc, so an update
 * trigger diff is the only reliable hook. Unfollows stay silent.)
 */
export const onUserFollowingChanged = onDocumentUpdated(
  {
    document: "users/{uid}",
    database: DATABASE_ID,
  },
  async (event) => {
    const followerUid = event.params.uid as string;
    const before = (event.data?.before.data()?.following as string[] | undefined) ?? [];
    const after = (event.data?.after.data()?.following as string[] | undefined) ?? [];
    const beforeSet = new Set(before);
    const added = after.filter((t) => t && !beforeSet.has(t) && t !== followerUid);
    if (added.length === 0) return;
    // A bulk write (migration/backfill) should not fan out notifications.
    if (added.length > 10) {
      logger.warn("skipping new_follower fanout for bulk following update", {
        followerUid,
        addedCount: added.length,
      });
      return;
    }
    const follower = (await db.collection("users").doc(followerUid).get()).data();
    const first = firstNameFromUser(follower);
    for (const target of added.filter((t) => hiddenAccountCanNotify(followerUid, t))) {
      await sendToUser(
        target,
        `${first} started following you`,
        "See what they're reading on SPINE.",
        { type: "new_follower", followerId: followerUid }
      );
    }
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
    // Default 60s would kill the function mid-wait (see delay below).
    timeoutSeconds: 300,
  },
  async (event) => {
    const postId = event.params.postId as string;
    const snap = event.data;
    if (!snap) return;
    const data = snap.data();
    if (data.type !== "finishedBook") return;
    const authorId = data.userId as string;
    if (!authorId) return;

    // Right after reviewing, the author is sent to the tier list to rank the book —
    // wait so the push can reflect the tier (and not tease a rank that isn't set yet).
    await new Promise((resolve) => setTimeout(resolve, 2 * 60 * 1000));

    // Re-read the post: the tier/rating may have landed while we waited, and the
    // author may have deleted the post entirely (in which case, stay silent).
    const freshSnap = await snap.ref.get();
    if (!freshSnap.exists) return;
    const fresh = freshSnap.data() ?? {};

    const author = (await db.collection("users").doc(authorId).get()).data();
    const first = firstNameFromUser(author);
    const { title: book, coverURL } = await bookInfo(data.bookId as string | undefined);
    const bookPart = book ?? "a book";
    const tier = (fresh.tier as string | undefined)?.trim();
    const rating = formatRating(fresh.rating);
    const caption = (fresh.caption as string | undefined)?.trim() ?? "";

    let title: string;
    let body: string;
    if (tier) {
      const teaser = teaser8Words(caption);
      title = rating !== null
        ? `${first} gave ${bookPart} a ${rating}`
        : `${first} finished ${bookPart}`;
      body = teaser ? teaser : "Open SPINE to read the full review.";
    } else {
      // Unranked: no mention of rating/rank — just the finish and their review.
      title = `${first} finished ${bookPart}`;
      body = caption || "See what they're reading on SPINE.";
    }

    const recipients = (await recipientUidsWhoFollow(authorId))
      .filter((uid) => hiddenAccountCanNotify(authorId, uid));
    const payload = {
      type: "friend_review_posted",
      postId,
    };
    for (const uid of recipients) {
      await sendToUser(uid, title, body, payload, coverURL);
    }
  }
);

/**
 * Book Blend pair doc (`bookBlends/{uidLow_uidHigh}`) changed:
 * - created as pending, or re-requested (declined → pending): blend_request push to the recipient.
 * - pending → ready (the accepter's device saved the generated result): blend_ready push to the requester.
 * - deleted while pending (requester undid the request, or account cleanup):
 *   silent push so the recipient's device removes the stale invite alert.
 * Declines stay silent. Both alert payloads deep-link via `blendId`.
 */
export const onBookBlendWritten = onDocumentWritten(
  {
    document: "bookBlends/{blendId}",
    database: DATABASE_ID,
  },
  async (event) => {
    const blendId = event.params.blendId as string;
    const before = event.data?.before.exists ? event.data.before.data() : undefined;
    const after = event.data?.after.exists ? event.data.after.data() : undefined;
    if (!after) {
      // Deleted. If it was still pending, the invite alert on the recipient's
      // device is now stale — tell their app to clear it. Best-effort: iOS may
      // defer or drop background pushes, in which case the alert just stays.
      const priorRecipient = before?.recipientId as string | undefined;
      if (before?.status === "pending" && priorRecipient) {
        await sendSilentToUser(priorRecipient, {
          type: "blend_request_withdrawn",
          blendId,
        });
      }
      return;
    }

    const beforeStatus = (before?.status as string | undefined) ?? null;
    const afterStatus = after.status as string | undefined;
    if (beforeStatus === afterStatus) return;

    const requesterId = after.requesterId as string | undefined;
    const recipientId = after.recipientId as string | undefined;
    if (!requesterId || !recipientId) return;

    const participants = (after.participants ?? {}) as Record<string, { firstName?: string }>;
    const nameOf = async (uid: string): Promise<string> => {
      const snapshotName = participants[uid]?.firstName?.trim();
      if (snapshotName) return snapshotName;
      return firstNameFromUser((await db.collection("users").doc(uid).get()).data());
    };

    if (afterStatus === "pending" && (beforeStatus === null || beforeStatus === "declined")) {
      if (!hiddenAccountCanNotify(requesterId, recipientId)) return;
      const requesterName = await nameOf(requesterId);
      await sendToUser(
        recipientId,
        `${requesterName} wants to make a Book Blend with you`,
        "Merge your libraries into one taste match — tap to accept.",
        { type: "blend_request", blendId, otherUserId: requesterId }
      );
      return;
    }

    if (afterStatus === "ready" && beforeStatus === "pending") {
      if (!hiddenAccountCanNotify(recipientId, requesterId)) return;
      const recipientName = await nameOf(recipientId);
      const score = (after.result as { score?: number } | undefined)?.score;
      await sendToUser(
        requesterId,
        `Your Book Blend with ${recipientName} is ready`,
        typeof score === "number"
          ? `You two scored ${score}%. Tap to watch it.`
          : "Tap to watch it.",
        { type: "blend_ready", blendId, otherUserId: recipientId }
      );
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
    if (!hiddenAccountCanNotify(likerId, authorId)) return;

    const liker = (await db.collection("users").doc(likerId).get()).data();
    const first = firstNameFromUser(liker);
    const { title: book, coverURL } = await bookInfo(postData.bookId as string | undefined);
    const title = book
      ? `${first} liked your review of ${book}`
      : `${first} liked your review`;

    await sendToUser(
      authorId,
      title,
      "Tap to open SPINE",
      { type: "review_liked", postId },
      coverURL
    );
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
    const { title: book, coverURL } = await bookInfo(postData.bookId as string | undefined);

    // Reply to another comment: comment_replied to the parent comment's author.
    const parentCommentId = d.parentCommentId as string | undefined;
    let replyTargetUid: string | null = null;
    if (parentCommentId) {
      const parent = await db.collection("comments").doc(parentCommentId).get();
      const parentUid = parent.data()?.userId as string | undefined;
      if (parentUid && parentUid !== commenterId && hiddenAccountCanNotify(commenterId, parentUid)) {
        replyTargetUid = parentUid;
        const replyTitle = book
          ? `${first} replied to your comment on ${book}`
          : `${first} replied to your comment`;
        const replyBody = teaser8Words(commentText);
        await sendToUser(
          replyTargetUid,
          replyTitle,
          replyBody,
          { type: "comment_replied", postId },
          coverURL
        );
      }
    }

    // Author: review_commented (not if self-comment; skip if they already got comment_replied)
    if (commenterId !== authorId && authorId !== replyTargetUid && hiddenAccountCanNotify(commenterId, authorId)) {
      const title = book
        ? `${first} commented on your review of ${book}`
        : `${first} replied to your review`;
      const preview = teaser8Words(commentText);
      const body = preview.length > 0 ? preview : "";
      await sendToUser(
        authorId,
        title,
        body,
        { type: "review_commented", postId },
        coverURL
      );
    }

    // Thread participants (exclude new commenter, post author, and the replied-to
    // commenter — each already notified above)
    const commentsSnap = await db.collection("comments").where("postId", "==", postId).get();
    const participantIds = new Set<string>();
    commentsSnap.forEach((doc) => {
      const uid = doc.data().userId as string | undefined;
      if (uid) participantIds.add(uid);
    });
    participantIds.delete(commenterId);
    participantIds.delete(authorId);
    if (replyTargetUid) participantIds.delete(replyTargetUid);

    const threadTitle = book
      ? `${first} also commented on the ${book} review you joined`
      : `${first} replied in a review thread you joined`;
    const threadBody = teaser8Words(commentText);

    for (const uid of participantIds) {
      await sendToUser(
        uid,
        threadTitle,
        threadBody,
        { type: "thread_commented", postId },
        coverURL
      );
    }
  }
);
