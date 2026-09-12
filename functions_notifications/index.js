const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();

const copy = {
  location_confirmed: "The meetup location was confirmed.",
  on_my_way: "Your meetup partner is on the way.",
  ready_to_verify: "Your meetup partner is ready to verify.",
  arrived: "Your meetup partner marked themselves as arrived.",
  meetup_completed: "Both participants arrived. The meetup is complete.",
};

async function tokensFor(uid) {
  const snap = await db.collection("users").doc(uid).collection("deviceTokens").limit(100).get();
  return snap.docs.filter(doc => doc.data().valid !== false).map(doc => ({token: doc.id, ref: doc.ref}));
}

exports.onMeetupStatusNotification = onDocumentUpdated(
  "meetups/{meetupId}",
  async (event) => {
    const before = event.data.before.data() || {};
    const after = event.data.after.data() || {};
    const previous = before.lastStatusEvent || {};
    const current = after.lastStatusEvent || {};
    const eventId = String(current.id || "");
    if (!eventId || eventId === String(previous.id || "")) return;

    const actorUid = String(current.actorUid || "").trim();
    const type = String(current.type || "").trim();
    const aUid = String(after.aUid || "").trim();
    const bUid = String(after.bUid || "").trim();
    const recipientUid = actorUid === aUid ? bUid : actorUid === bUid ? aUid : "";
    if (!recipientUid || !copy[type]) return;

    const blocks = await db.getAll(db.doc(`users/${recipientUid}/blocks/${actorUid}`), db.doc(`users/${actorUid}/blocks/${recipientUid}`));
    if (blocks.some(snap => snap.exists)) return;
    const tokens = await tokensFor(recipientUid);
    if (tokens.length === 0) {
      logger.info("Meetup status has no recipient tokens", { meetupId: event.params.meetupId, type });
      return;
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens.map(item => item.token),
      notification: { title: "Meetup update", body: copy[type] },
      data: {
        type: "meetup",
        meetupId: event.params.meetupId,
        chatId: String(after.chatId || event.params.meetupId),
        status: type,
        eventId,
        otherUid: actorUid,
      },
      android: {
        priority: "high",
        notification: { channelId: "chat_alerts", sound: "default", tag: eventId },
      },
      apns: { headers: {"apns-collapse-id": eventId.slice(0, 64)}, payload: { aps: { sound: "default" } } },
    });
    const invalid = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);
    await Promise.all(response.responses.map((result, i) =>
      !result.success && invalid.has(result.error?.code) ? tokens[i].ref.delete() : Promise.resolve()));
    logger.info("Meetup status notification sent", {
      meetupId: event.params.meetupId,
      type,
      success: response.successCount,
      failure: response.failureCount,
    });
  },
);

function isMemberDoc(doc) {
  return doc.id !== "current" && doc.id !== "partySettings";
}

function stringList(value) {
  return Array.isArray(value)
    ? value.map((item) => String(item).trim().toLowerCase())
      .filter((keyword) => keyword && !isLowQualityKeyword(keyword))
    : [];
}

function isLowQualityKeyword(keyword) {
  if (!/^[a-z0-9][a-z0-9 '\-]{0,48}$/.test(keyword) || /(.)\1{4,}/.test(keyword)) {
    return true;
  }
  const filler = new Set(["a", "an", "and", "her", "his", "its", "my", "our", "the", "their", "your"]);
  const words = keyword.split(/\s+/).filter(Boolean);
  return words.length >= 4 && words.filter((word) => filler.has(word)).length >= 2;
}

function keywordGroups(profile) {
  const groups = profile.keywords || profile.keywordGroups || {};
  return {
    wants: stringList(
      groups["Searching For"] || groups.searchingFor ||
      profile["Searching For"] || profile.SearchingFor,
    ),
    offers: stringList(
      groups["Can Provide"] || groups.canProvide ||
      profile["Can Provide"] || profile.CanProvide,
    ),
  };
}

function topCounts(counts, limit = 12) {
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, limit)
    .map(([keyword, count]) => ({ keyword, count }));
}

exports.onPartyNetworkInsightRequest = onDocumentWritten(
  {document: "partyNetworkRequests/{uid}", retry: true, timeoutSeconds: 300},
  async (event) => {
    if (!event.data.after.exists) return;
    const before = event.data.before.exists ? event.data.before.data() || {} : {};
    const after = event.data.after.data() || {};
    const nonce = String(after.requestNonce || "");
    const uid = String(event.params.uid || "").trim();
    if (!nonce || nonce === String(before.requestNonce || "") || after.ownerUid !== uid) return;

    const permitted = await db.runTransaction(async tx => {
      const throttle = db.doc(`partyNetworkRateLimits/${uid}`);
      const [request, previousRequest] = await tx.getAll(event.data.after.ref, throttle);
      if (request.data()?.requestNonce !== nonce) return false;
      const last = previousRequest.data() || {};
      if (last.nonce !== nonce && Number(last.at || 0) + 60000 > Date.now()) {
        tx.set(event.data.after.ref, {status: 'rate_limited'}, {merge: true});
        return false;
      }
      tx.set(throttle, {nonce, at: Date.now()});
      return true;
    });
    if (!permitted) return;
    const ownerParty = await db.collection("users").doc(uid).collection("party").limit(250).get();
    const directUids = ownerParty.docs.filter(isMemberDoc).map((doc) => doc.id.trim()).filter(Boolean);
    const directSet = new Set(directUids);
    const secondDegree = new Set();
    let sharingConnectors = 0;

    for (const connectorUid of directUids) {
      const sharing = await db.collection("users").doc(connectorUid)
        .collection("settings").doc("partyNetwork").get();
      if (sharing.data()?.sharingEnabled !== true) continue;
      sharingConnectors += 1;
      const connectorParty = await db.collection("users").doc(connectorUid)
        .collection("party").limit(250).get();
      for (const candidate of connectorParty.docs.filter(isMemberDoc)) {
        const candidateUid = candidate.id.trim();
        if (candidateUid && candidateUid !== uid && !directSet.has(candidateUid)) {
          secondDegree.add(candidateUid);
        }
      }
    }

    const wants = new Map();
    const offers = new Map();
    const moderation = await db.collection("keywordModeration")
      .where("hidden", "==", true).limit(500).get();
    const suppressedKeywords = new Set(moderation.docs
      .map((doc) => String(doc.data().normalizedKeyword || "").trim().toLowerCase())
      .filter(Boolean));
    let consentingProfiles = 0;
    for (const candidateUid of [...secondDegree].slice(0, 500)) {
      const [sharing, profile] = await Promise.all([
        db.collection("users").doc(candidateUid).collection("settings").doc("partyNetwork").get(),
        db.collection("profiles").doc(candidateUid).get(),
      ]);
      if (sharing.data()?.sharingEnabled !== true || !profile.exists) continue;
      consentingProfiles += 1;
      const groups = keywordGroups(profile.data() || {});
      for (const keyword of groups.wants) {
        if (!suppressedKeywords.has(keyword)) wants.set(keyword, (wants.get(keyword) || 0) + 1);
      }
      for (const keyword of groups.offers) {
        if (!suppressedKeywords.has(keyword)) offers.set(keyword, (offers.get(keyword) || 0) + 1);
      }
    }

    const opportunities = new Map();
    for (const keyword of wants.keys()) {
      if (offers.has(keyword)) {
        opportunities.set(keyword, wants.get(keyword) * offers.get(keyword));
      }
    }

    await db.runTransaction(async tx => {
      const fresh = await tx.get(event.data.after.ref);
      if (fresh.data()?.requestNonce !== nonce) return;
      tx.set(event.data.after.ref, {
      status: "ready",
      result: {
        directMembers: directUids.length,
        sharingConnectors,
        secondDegreeProfiles: consentingProfiles,
        topWants: topCounts(wants),
        topOffers: topCounts(offers),
        opportunities: topCounts(opportunities),
      },
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    });
  },
);

function withoutKeyword(profile, normalized) {
  const next = { ...profile };
  const clean = (value) => Array.isArray(value)
    ? value.filter((item) => String(item).trim().toLowerCase() !== normalized)
    : value;
  for (const key of ["SearchingFor", "CanProvide", "Searching For", "Can Provide"]) {
    if (Object.prototype.hasOwnProperty.call(next, key)) next[key] = clean(next[key]);
  }
  for (const groupKey of ["keywords", "keywordGroups"]) {
    const groups = next[groupKey];
    if (!groups || typeof groups !== "object") continue;
    next[groupKey] = { ...groups };
    for (const key of ["Searching For", "Can Provide", "searchingFor", "canProvide"]) {
      if (Object.prototype.hasOwnProperty.call(next[groupKey], key)) {
        next[groupKey][key] = clean(next[groupKey][key]);
      }
    }
  }
  return next;
}

exports.onKeywordReportCreated = onDocumentCreated(
  {document: "keywordReports/{reportId}", retry: true},
  async (event) => {
    const report = event.data?.data() || {};
    const normalized = String(report.normalizedKeyword || "").trim().toLowerCase();
    if (!normalized) return;

    const reports = await db.collection("keywordReports")
      .where("normalizedKeyword", "==", normalized).limit(200).get();
    const reporterUids = new Set();
    const targetUids = new Set();
    for (const doc of reports.docs) {
      const data = doc.data() || {};
      const reporterUid = String(data.reporterUid || "").trim();
      const targetUid = String(data.targetUid || "").trim();
      if (reporterUid) reporterUids.add(reporterUid);
      if (targetUid) targetUids.add(targetUid);
    }

    const moderationId = Buffer.from(normalized).toString("base64url").slice(0, 120);
    const moderationRef = db.collection("keywordModeration").doc(moderationId);
    const hidden = reporterUids.size >= 3;
    const shouldHide = await db.runTransaction(async tx => {
      const prior = await tx.get(moderationRef);
      const alreadyHidden = prior.data()?.hidden === true;
      tx.set(moderationRef, {
        normalizedKeyword: normalized,
        reportCount: Math.max(reports.size, Number(prior.data()?.reportCount || 0)),
        distinctReporters: Math.max(reporterUids.size, Number(prior.data()?.distinctReporters || 0)),
        hidden: hidden || alreadyHidden,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(hidden && !alreadyHidden ? {hiddenAt: admin.firestore.FieldValue.serverTimestamp()} : {}),
      }, {merge: true});
      return hidden || alreadyHidden;
    });
    if (!shouldHide) return;

    for (const targetUid of [...targetUids].slice(0, 50)) {
      const profileRef = db.collection("profiles").doc(targetUid);
      const userRef = db.collection("users").doc(targetUid);
      const enforcement = db.collection("keywordEnforcement").doc(targetUid);
      const strike = enforcement.collection('keywords').doc(moderationId);
      await db.runTransaction(async tx => {
        const [profileSnap, userSnap, priorStrike] = await tx.getAll(profileRef, userRef, strike);
        if (profileSnap.exists) tx.set(profileRef, {
          ...withoutKeyword(profileSnap.data() || {}, normalized),
          moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (userSnap.exists) tx.set(userRef, {
          ...withoutKeyword(userSnap.data() || {}, normalized),
          keywordLastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        if (!priorStrike.exists && userSnap.exists) {
          tx.create(strike, {normalizedKeyword: normalized, createdAt: admin.firestore.FieldValue.serverTimestamp()});
          tx.set(enforcement, {
            strikeCount: admin.firestore.FieldValue.increment(1), lastKeyword: normalized,
            lastStrikeAt: admin.firestore.FieldValue.serverTimestamp(), reviewRequired: true,
          }, {merge: true});
        }
      });
    }
    logger.warn("Keyword globally suppressed after independent reports", {
      normalizedKeyword: normalized,
      distinctReporters: reporterUids.size,
      affectedProfiles: targetUids.size,
    });
  },
);
