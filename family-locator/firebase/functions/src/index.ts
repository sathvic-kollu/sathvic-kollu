import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {DocumentReference, FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging, MulticastMessage} from "firebase-admin/messaging";
import {logger} from "firebase-functions";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {Alert, decideDelivery, digestSummary, isStale, Settings, windowContains, localClock} from "./policy";

initializeApp();
const db = getFirestore();
const HISTORY_DAYS = 30;

interface FamilyDoc {
  settings?: Settings;
  tzOffsetMinutes?: number;
}

async function tokensFor(familyId: string, filter: (m: FirebaseFirestore.DocumentData, id: string) => boolean) {
  const members = await db.collection(`families/${familyId}/members`).get();
  const tokens: {token: string; ref: DocumentReference}[] = [];
  for (const m of members.docs) {
    if (!filter(m.data(), m.id)) continue;
    for (const t of (m.data().fcmTokens ?? []) as string[]) tokens.push({token: t, ref: m.ref});
  }
  return tokens;
}

/** Sends, then forgets tokens FCM says are dead (app uninstalled). */
async function send(
  targets: {token: string; ref: DocumentReference}[],
  message: Omit<MulticastMessage, "tokens">,
) {
  if (targets.length === 0) return;
  const res = await getMessaging().sendEachForMulticast({...message, tokens: targets.map((t) => t.token)});
  await Promise.all(res.responses.map((r, i) => {
    const code = r.error?.code;
    if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
      return targets[i].ref.update({fcmTokens: FieldValue.arrayRemove(targets[i].token)});
    }
    return null;
  }));
}

function title(type: string): string {
  switch (type) {
  case "sos": return "🆘 SOS";
  case "trackingOff":
  case "permissionLost": return "⚠️ Location stopped";
  case "lowBattery": return "🔋 Low battery";
  case "arrived":
  case "left": return "📍 Places";
  case "checkIn": return "✅ Check-in";
  default: return "Family Locator";
  }
}

async function notifyParents(familyId: string, heading: string, body: string, urgent: boolean) {
  const targets = await tokensFor(familyId, (m) => m.role === "parent");
  await send(targets, {
    notification: {title: heading, body},
    android: {
      priority: "high",
      notification: {channelId: urgent ? "urgent" : "alerts", sound: "default"},
    },
    apns: {payload: {aps: {sound: urgent ? {critical: true, name: "default", volume: 1} : "default"}}},
  });
}

/** Every new alert: push now, hold for the quiet-hours summary, or feed only. */
export const onAlertCreated = onDocumentCreated("families/{familyId}/alerts/{alertId}", async (event) => {
  const alert = event.data?.data() as Alert | undefined;
  if (!alert) return;
  const familyId = event.params.familyId;
  const family = ((await db.doc(`families/${familyId}`).get()).data() ?? {}) as FamilyDoc;
  const zone = alert.zoneId ?
    (await db.doc(`families/${familyId}/zones/${alert.zoneId}`).get()).data() :
    undefined;
  const delivery = decideDelivery(alert, family.settings ?? {}, family.tzOffsetMinutes ?? 0, zone?.window);
  if (delivery === "now") {
    await notifyParents(familyId, title(alert.type), alert.message, Boolean(alert.urgent));
  } else if (delivery === "digest") {
    await db.doc(`families/${familyId}/digest/${alert.id}`).set(alert);
  }
});

/** "Ring loudly": a high-priority data push wakes the child's phone. */
export const onCommandCreated = onDocumentCreated("families/{familyId}/commands/{commandId}", async (event) => {
  const command = event.data?.data();
  if (!command) return;
  const targets = await tokensFor(event.params.familyId, (_, id) => id === command.childId);
  await send(targets, {
    data: {type: command.type, from: String(command.from ?? ""), commandId: event.params.commandId},
    android: {priority: "high", ttl: 5 * 60 * 1000},
    apns: {headers: {"apns-priority": "10"}, payload: {aps: {contentAvailable: true}}},
  });
});

/**
 * Silence is the failure parents never hear about: a dead battery, a
 * revoked permission, a force-stopped app. Raise it explicitly, once.
 */
export const checkStalePhones = onSchedule("every 10 minutes", async () => {
  const now = Date.now();
  const families = await db.collection("families").get();
  for (const f of families.docs) {
    const family = f.data() as FamilyDoc;
    const staleAfter = family.settings?.staleAfterMinutes ?? 30;
    const children = await f.ref.collection("children").get();
    for (const c of children.docs) {
      const child = c.data();
      const stale = isStale(child, now, staleAfter);
      if (stale && !child.staleAlerted) {
        const id = `stale-${c.id}-${now}`;
        await f.ref.collection("alerts").doc(id).set({
          id,
          childId: c.id,
          type: "trackingOff",
          at: now,
          message: `No location from ${child.name ?? "your child"} for ${staleAfter}+ min. ` +
            "Their phone may be off, out of battery or offline.",
          urgent: true,
        });
        await c.ref.update({staleAlerted: true});
      } else if (!stale && child.staleAlerted) {
        await c.ref.update({staleAlerted: false});
      }
    }

    // Quiet hours over? Send what was held as one notification.
    const quiet = family.settings?.quietHours;
    if (quiet && windowContains(quiet, localClock(now, family.tzOffsetMinutes ?? 0))) continue;
    const held = await f.ref.collection("digest").get();
    if (held.empty) continue;
    const alerts = held.docs.map((d) => d.data() as Alert);
    await notifyParents(f.id, "While you were in quiet hours", digestSummary(alerts, family.tzOffsetMinutes ?? 0), false);
    const batch = db.batch();
    held.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
});

/** Location history is deleted after 30 days. Families don't need a dossier. */
export const pruneHistory = onSchedule("every day 03:00", async () => {
  const cutoff = Date.now() - HISTORY_DAYS * 24 * 60 * 60 * 1000;
  for (;;) {
    const old = await db.collectionGroup("history").where("at", "<", cutoff).limit(400).get();
    if (old.empty) break;
    const batch = db.batch();
    old.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    logger.info(`pruned ${old.size} history points`);
  }
  for (const col of ["views", "alerts"]) {
    const old = await db.collectionGroup(col).where("at", "<", cutoff).limit(400).get();
    const batch = db.batch();
    old.docs.forEach((d) => batch.delete(d.ref));
    if (!old.empty) await batch.commit();
  }
});

async function deleteWhere(col: FirebaseFirestore.CollectionReference, field: string, value: string) {
  for (;;) {
    const snap = await col.where(field, "==", value).limit(400).get();
    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

/**
 * In-app account deletion (required by Google Play and the App Store).
 * Child: erases their profile, location history, alerts, view log, tasks
 * and commands. Parent: removes their membership; if no parent is left,
 * the whole family is erased. Finally the sign-in itself is deleted.
 */
export const deleteMyData = onCall(async (request) => {
  const uid = request.auth?.uid;
  const familyId = request.data?.familyId;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (typeof familyId !== "string") throw new HttpsError("invalid-argument", "familyId is required.");

  const family = db.doc(`families/${familyId}`);
  const member = await family.collection("members").doc(uid).get();
  if (member.exists) {
    if (member.data()?.role === "child") {
      await db.recursiveDelete(family.collection("children").doc(uid));
      for (const col of ["alerts", "views", "tasks", "commands"]) {
        await deleteWhere(family.collection(col), "childId", uid);
      }
      await member.ref.delete();
    } else {
      await member.ref.delete();
      const parentsLeft = await family.collection("members").where("role", "==", "parent").limit(1).get();
      if (parentsLeft.empty) await db.recursiveDelete(family);
    }
  }
  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    logger.warn(`auth user ${uid} not deleted`, e);
  }
  logger.info(`deleted data for ${uid} in ${familyId}`);
});
