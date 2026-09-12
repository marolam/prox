/**
 * functions/src/lib/push.ts
 *
 * Push notification triggers for Prox:
 *  - onNewChatMessage: notify chat participants of a new message
 *  - onNewMatch: notify users when a match is created
 *  - onMeetupUpdate: notify participants when meetup status changes
 *
 * Soft assumptions (log + return on missing):
 *  - Chats:    /chats/{chatId} with participants: string[], lastMessage?, lastFrom?
 *  - Messages: /chats/{chatId}/messages/{messageId} with from: string, text?: string, imageUrl?: string
 *  - Matches:  /matches/{matchId} with participants: string[] OR userIds: string[] OR aUid/bUid
 *  - Meetups:  /meetups/{meetupId} with aUid/bUid (or participants), status: string
 *  - Tokens:   /users/{uid}/deviceTokens/{tokenId}
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

function uniqStrings(xs: string[]): string[] {
  return Array.from(new Set(xs.filter((s) => typeof s === "string" && s.trim().length > 0)));
}

/**
 * Helper: fetch all device tokens for a set of user IDs.
 */
type DeviceToken = {token: string; ref: FirebaseFirestore.DocumentReference};

async function getDeviceTokensForUsers(userIds: string[], senderUid = ''): Promise<DeviceToken[]> {
  const sets = await Promise.all(uniqStrings(userIds).map(async uid => {
    if ((await db.doc(`accountDeletions/${uid}`).get()).exists) return [];
    if (senderUid) {
      const blocks = await db.getAll(db.doc(`users/${uid}/blocks/${senderUid}`), db.doc(`users/${senderUid}/blocks/${uid}`));
      if (blocks.some(snap => snap.exists)) return [];
    }
    const snapshot = await db.collection('users').doc(uid).collection('deviceTokens').limit(100).get();
    return snapshot.docs.filter(doc => doc.data().valid !== false).map(doc => ({token: doc.id, ref: doc.ref}));
  }));
  return [...new Map(sets.flat().map(item => [item.token, item])).values()];
}

async function sendToTokens(tokens: DeviceToken[], title: string, body: string, data: Record<string, string> = {}) {
  const invalid = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);
  const eventKey = data.messageId || data.matchId || `${data.meetupId || ''}_${data.status || ''}`;
  for (let offset = 0; offset < tokens.length; offset += 500) {
    const group = tokens.slice(offset, offset + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: group.map(item => item.token), notification: {title, body}, data: {...data, eventId: eventKey},
      android: {priority: 'high', notification: {channelId: 'chat_alerts', sound: 'default', tag: eventKey}},
      apns: {headers: {'apns-priority': '10', 'apns-collapse-id': eventKey.slice(0, 64)}, payload: {aps: {sound: 'default'}}},
    });
    await Promise.all(response.responses.map((result, i) =>
      !result.success && invalid.has(result.error?.code || '') ? group[i].ref.delete() : Promise.resolve()));
    functions.logger.info('push.batch', {success: response.successCount, failure: response.failureCount});
  }
}

/**
 * Trigger: new chat message => notify other participants.
 */
export const onNewChatMessage = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const { chatId, messageId } = context.params;
    const messageData = snap.data() || {};

    const senderUid =
      (messageData.from as string | undefined) ??
      (messageData.senderUid as string | undefined) ??
      "";

    const textPreview =
      (messageData.text as string | undefined) ??
      (messageData.content as string | undefined) ??
      "";

    const hasImage = typeof messageData.imageUrl === "string" && (messageData.imageUrl as string).length > 0;

    console.log("[push:onNewChatMessage] New message", {
      chatId,
      messageId,
      senderUid,
      hasImage,
    });

    // Fetch chat metadata for participants.
    const chatRef = db.collection("chats").doc(chatId);
    const chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      console.warn("[push:onNewChatMessage] Chat doc missing for", chatId);
      return;
    }

    const chat = chatSnap.data() || {};
    if (chat.closedAt) return;
    const participants = Array.isArray(chat.participants) ? (chat.participants as string[]) : [];
    const chatType = (chat.type as string | undefined) ?? "direct";
    const gate = (chat.chatGate as Record<string, unknown> | undefined) ?? {};
    const gateStatus = String(gate.status ?? "").trim();
    const gateRequestedBy = String(gate.requestedBy ?? "").trim();
    const isChatRequest = gateStatus === "requested" && gateRequestedBy === senderUid;

    if (!participants.length || !participants.includes(senderUid)) {
      console.warn("[push:onNewChatMessage] No participants in chat", chatId);
      return;
    }

    const targetUids = participants.filter((uid) => uid && uid !== senderUid);
    if (!targetUids.length) {
      console.log("[push:onNewChatMessage] No other participants to notify");
      return;
    }

    const tokens = await getDeviceTokensForUsers(targetUids, senderUid);
    if (!tokens.length) {
      console.log("[push:onNewChatMessage] No tokens for participants", { targetUids });
      return;
    }

    let hasPartyContext = false;
    try {
      for (const targetUid of targetUids) {
        if (!targetUid || !senderUid) continue;
        const partySnap = await db
          .collection("users")
          .doc(targetUid)
          .collection("party")
          .doc(senderUid)
          .get();
        if (partySnap.exists) {
          hasPartyContext = true;
          break;
        }
      }
    } catch (e) {
      console.warn("[push:onNewChatMessage] party context check failed", e);
    }

    let title = "New message";
    if (isChatRequest) {
      title = hasPartyContext ? "Party chat request" : "New chat request";
    } else if (hasPartyContext) {
      title = "Party member message";
    } else if (chatType === "group_moderated") {
      title = "Group bridge message";
    }
    const truncated =
      textPreview && textPreview.length > 80 ? textPreview.slice(0, 77) + "..." : textPreview;

    const body = truncated || (hasImage ? "📷 Photo" : "You have a new message in Prox");

    await sendToTokens(tokens, title, body, {
      type: "message",
      chatId,
      messageId,
      fromUid: senderUid,
      otherUid: senderUid,
      senderUid,
      chatType,
      chatRequest: String(isChatRequest),
      isPartyContext: String(hasPartyContext),
      ts: String(Date.now()),
    });
  });

/**
 * Trigger: new match doc => notify both users.
 */
export const onNewMatch = functions.firestore
  .document("matches/{matchId}")
  .onCreate(async (snap, context) => {
    const { matchId } = context.params;
    const data = snap.data() || {};

    let userIds: string[] = [];

    if (Array.isArray(data.participants)) {
      userIds = (data.participants as string[]).filter(Boolean);
    } else if (Array.isArray(data.userIds)) {
      userIds = (data.userIds as string[]).filter(Boolean);
    } else if (typeof data.aUid === "string" && typeof data.bUid === "string") {
      userIds = [data.aUid, data.bUid];
    }

    userIds = uniqStrings(userIds);
    if (userIds.length === 2) {
      const blocks = await db.getAll(db.doc(`users/${userIds[0]}/blocks/${userIds[1]}`), db.doc(`users/${userIds[1]}/blocks/${userIds[0]}`));
      if (blocks.some(snap => snap.exists)) return;
    }

    if (!userIds.length) {
      console.warn("[push:onNewMatch] No participants/userIds/aUid/bUid on match", matchId);
      return;
    }

    console.log("[push:onNewMatch] New match", { matchId, userIds });

    const tokens = await getDeviceTokensForUsers(userIds);
    if (!tokens.length) {
      console.log("[push:onNewMatch] No tokens for match participants", { matchId, userIds });
      return;
    }

    const rawKeywords = data.lastSharedKeywords;
    const sharedKeywords = Array.isArray(rawKeywords)
      ? rawKeywords.map((k) => String(k || "").trim()).filter((k) => k.length > 0)
      : [];
    const keywordCount = sharedKeywords.length;
    const keywordLabel = sharedKeywords.slice(0, 3).join(", ");

    let title = "You have a new match";
    let body = "Open Prox to say hi!";
    if (keywordCount > 0) {
      if (keywordCount >= 4) {
        title = "High-signal match unlocked";
      } else if (keywordCount >= 2) {
        title = "Strong keyword match";
      }

      body = keywordCount === 1
        ? `Matched on ${keywordLabel}.`
        : `Matched on ${keywordCount} keywords: ${keywordLabel}${keywordCount > 3 ? ", ..." : ""}.`;
    }

    await sendToTokens(tokens, title, body, {
      type: "match",
      matchId,
      keywordCount: String(keywordCount),
      keywordHits: sharedKeywords.join(","),
      ts: String(Date.now()),
    });
  });

/**
 * Trigger: meetup status changes => notify participants.
 *
 * We only send when `status` actually changes.
 */
export const onMeetupUpdate = functions.firestore
  .document("meetups/{meetupId}")
  .onWrite(async (change, context) => {
    const { meetupId } = context.params;

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    if (!after) {
      console.log("[push:onMeetupUpdate] Meetup deleted", meetupId);
      return;
    }

    // The notifications codebase handles explicit actor status events.
    if (after.lastStatusEvent?.id && after.lastStatusEvent.id !== before?.lastStatusEvent?.id) return;
    const beforeStatus = (before?.status as string | undefined) ?? "";
    const afterStatus = (after.status as string | undefined) ?? "";

    if (beforeStatus === afterStatus) {
      console.log("[push:onMeetupUpdate] Status unchanged; skipping push", meetupId);
      return;
    }

    // Participants: prefer explicit aUid/bUid; else after.participants.
    const aUid = (after.aUid as string | undefined) ?? "";
    const bUid = (after.bUid as string | undefined) ?? "";
    const participantsFromAB = uniqStrings([aUid, bUid]);
    const participantsFromArray = Array.isArray(after.participants)
      ? uniqStrings((after.participants as string[]).filter(Boolean))
      : [];

    const participants = participantsFromAB.length ? participantsFromAB : participantsFromArray;

    if (!participants.length) {
      console.warn("[push:onMeetupUpdate] No participants on meetup", meetupId);
      return;
    }

    console.log("[push:onMeetupUpdate] Status change", {
      meetupId,
      beforeStatus,
      afterStatus,
      participants,
    });

    const tokens = await getDeviceTokensForUsers(participants);
    if (!tokens.length) {
      console.log("[push:onMeetupUpdate] No tokens for participants", { meetupId, participants });
      return;
    }

    let title = "Meetup updated";
    let body = `Status: ${afterStatus || "updated"}`;

    // Prox statuses observed in app: live/completed/expired/cancelled
    if (afterStatus === "live") {
      title = "Meetup started";
      body = "Open Prox for location details.";
    } else if (afterStatus === "completed") {
      title = "Meetup completed";
      body = "Leave a rating for your partner.";
    } else if (afterStatus === "expired") {
      title = "Meetup expired";
      body = "Looks like nobody arrived in time.";
    } else if (afterStatus === "cancelled") {
      title = "Meetup cancelled";
      body = "Your meetup has been cancelled.";
    }

    await sendToTokens(tokens, title, body, {
      type: "meetup",
      meetupId,
      status: afterStatus,
      ts: String(Date.now()),
    });
  });
