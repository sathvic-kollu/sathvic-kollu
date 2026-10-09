// Runs the deployed functions' handlers against the Firestore/Auth emulators:
//   npm run test:emulator
import {after, beforeEach, describe, test} from "node:test";
import assert from "node:assert/strict";
import functionsTest from "firebase-functions-test";

const fft = functionsTest({projectId: process.env.GCLOUD_PROJECT ?? "demo-family-locator"});
// Imported after functionsTest() so the admin SDK picks up the emulator config.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const fns = require("./index") as typeof import("./index");
import {getFirestore} from "firebase-admin/firestore";

const db = getFirestore();
const F = "fam1";
const now = Date.now();
const MIN = 60_000;
const allDay = {days: [1, 2, 3, 4, 5, 6, 7], start: 0, end: 24 * 60};

async function clear() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const project = process.env.GCLOUD_PROJECT;
  await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`, {method: "DELETE"});
}

async function seedFamily(settings: object = {}) {
  await db.doc(`families/${F}`).set({createdBy: "mum", settings, tz: "Europe/London"});
  await db.doc(`families/${F}/members/mum`).set({role: "parent", name: "Mum"});
  for (const kid of ["mia", "leo"]) {
    await db.doc(`families/${F}/members/${kid}`).set({role: "child", name: kid});
    await db.doc(`families/${F}/children/${kid}`).set({id: kid, name: kid, health: {lastSeen: now}});
  }
}

async function runAlert(alert: Record<string, unknown>) {
  const path = `families/${F}/alerts/${alert.id}`;
  await db.doc(path).set(alert);
  const snap = fft.firestore.makeDocumentSnapshot(alert, path);
  await wrap(fns.onAlertCreated)({data: snap, params: {familyId: F, alertId: alert.id}});
}

// Loosely typed: the harness accepts partial events for every trigger type.
const wrap = (fn: unknown) =>
  (fft.wrap as unknown as (f: unknown) => (event: unknown) => Promise<unknown>)(fn);

const exists = async (path: string) => (await db.doc(path).get()).exists;

beforeEach(clear);
after(() => fft.cleanup());

describe("onAlertCreated", () => {
  test("non-urgent alerts during quiet hours are held for the digest", async () => {
    await seedFamily({quietHours: allDay});
    await runAlert({id: "a1", childId: "mia", type: "lowBattery", at: now, message: "Mia's phone is at 12%"});
    assert.ok(await exists(`families/${F}/digest/a1`));
  });

  test("SOS is never held, even in quiet hours", async () => {
    await seedFamily({quietHours: allDay});
    await runAlert({id: "s1", childId: "mia", type: "sos", at: now, message: "Mia pressed SOS", urgent: true});
    assert.equal(await exists(`families/${F}/digest/s1`), false);
  });

  test("place alerts outside the place's schedule are feed-only", async () => {
    await seedFamily({quietHours: allDay});
    await db.doc(`families/${F}/zones/school`).set({id: "school", window: {days: [], start: 0, end: 60}});
    await runAlert({id: "z1", childId: "mia", type: "arrived", at: now, zoneId: "school", message: "Mia arrived at School"});
    assert.equal(await exists(`families/${F}/digest/z1`), false);
  });
});

describe("checkStalePhones", () => {
  const run = () => wrap(fns.checkStalePhones)({});

  test("raises one tracking-stopped alert for a silent phone, and re-arms when it's back", async () => {
    await seedFamily({staleAfterMinutes: 30});
    await db.doc(`families/${F}/children/mia`).update({health: {lastSeen: now - 90 * MIN}});
    await run();
    let alerts = await db.collection(`families/${F}/alerts`).where("type", "==", "trackingOff").get();
    assert.equal(alerts.size, 1);
    assert.equal(alerts.docs[0].data().childId, "mia");
    assert.equal((await db.doc(`families/${F}/children/mia`).get()).data()?.staleAlerted, true);

    await run(); // no duplicate
    alerts = await db.collection(`families/${F}/alerts`).where("type", "==", "trackingOff").get();
    assert.equal(alerts.size, 1);

    await db.doc(`families/${F}/children/mia`).update({health: {lastSeen: Date.now()}});
    await run();
    assert.equal((await db.doc(`families/${F}/children/mia`).get()).data()?.staleAlerted, false);
  });

  test("a paused child is not reported", async () => {
    await seedFamily({staleAfterMinutes: 30});
    await db.doc(`families/${F}/children/leo`).update({health: {lastSeen: now - 90 * MIN}, pausedUntil: now + 60 * MIN});
    await run();
    const alerts = await db.collection(`families/${F}/alerts`).get();
    assert.equal(alerts.size, 0);
  });

  test("held alerts are sent and cleared once quiet hours are over", async () => {
    await seedFamily({}); // no quiet hours now
    await db.doc(`families/${F}/digest/a1`).set({id: "a1", childId: "mia", type: "lowBattery", at: now, message: "x"});
    await run();
    assert.equal((await db.collection(`families/${F}/digest`).get()).size, 0);
  });
});

describe("deleteMyData", () => {
  const call = (uid: string) =>
    wrap(fns.deleteMyData)({data: {familyId: F}, auth: {uid, token: {}}});

  test("a child's data is erased and siblings are untouched", async () => {
    await seedFamily();
    await db.doc(`families/${F}/children/mia/history/h1`).set({at: now});
    await db.doc(`families/${F}/alerts/a1`).set({childId: "mia", at: now});
    await db.doc(`families/${F}/alerts/a2`).set({childId: "leo", at: now});
    await db.doc(`families/${F}/views/v1`).set({childId: "mia", at: now});
    await db.doc(`families/${F}/tasks/t1`).set({childId: "mia"});
    await call("mia");
    for (const p of ["children/mia", "children/mia/history/h1", "alerts/a1", "views/v1", "tasks/t1", "members/mia"]) {
      assert.equal(await exists(`families/${F}/${p}`), false, p);
    }
    assert.ok(await exists(`families/${F}/children/leo`));
    assert.ok(await exists(`families/${F}/alerts/a2`));
  });

  test("the last parent leaving erases the whole family", async () => {
    await seedFamily();
    await db.doc(`families/${F}/children/mia/history/h1`).set({at: now});
    await call("mum");
    assert.equal(await exists(`families/${F}`), false);
    assert.equal(await exists(`families/${F}/children/mia/history/h1`), false);
  });

  test("with another parent left, only the leaver's membership goes", async () => {
    await seedFamily();
    await db.doc(`families/${F}/members/dad`).set({role: "parent", name: "Dad"});
    await call("mum");
    assert.equal(await exists(`families/${F}/members/mum`), false);
    assert.ok(await exists(`families/${F}/children/mia`));
  });

  test("requires sign-in", async () => {
    await assert.rejects(wrap(fns.deleteMyData)({data: {familyId: F}}));
  });
});

describe("pruneHistory", () => {
  test("deletes location history, alerts and views older than 30 days", async () => {
    await seedFamily();
    const old = now - 31 * 24 * 60 * MIN;
    await db.doc(`families/${F}/children/mia/history/old`).set({at: old});
    await db.doc(`families/${F}/children/mia/history/new`).set({at: now});
    await db.doc(`families/${F}/alerts/old`).set({at: old, childId: "mia"});
    await db.doc(`families/${F}/views/old`).set({at: old, childId: "mia"});
    await wrap(fns.pruneHistory)({});
    assert.equal(await exists(`families/${F}/children/mia/history/old`), false);
    assert.ok(await exists(`families/${F}/children/mia/history/new`));
    assert.equal(await exists(`families/${F}/alerts/old`), false);
    assert.equal(await exists(`families/${F}/views/old`), false);
  });
});
