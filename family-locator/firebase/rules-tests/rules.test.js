// Security-rule tests against the Firestore emulator. Each write mirrors
// what lib/data/firestore_backend.dart actually sends.
//   npm install && npm test        (needs Java for the emulator)
import {readFileSync} from "node:fs";
import {after, before, beforeEach, describe, test} from "node:test";
import {assertFails, assertSucceeds, initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, doc, getDoc, getDocs, limit, orderBy, query, setDoc, updateDoc, where,
} from "firebase/firestore";

let env;
const F = "fam1";
const now = Date.now();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-family-locator",
    firestore: {rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8")},
  });
});
after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

/** Parent "mum" creates the family exactly like createFamily(). */
async function createFamily() {
  const db = as("mum");
  await setDoc(doc(db, `families/${F}`), {createdBy: "mum", settings: {lowBatteryPct: 15}, tz: "Europe/London"});
  await setDoc(doc(db, `families/${F}/members/mum`), {role: "parent", name: "Mum"});
  return db;
}

async function invite(code, role, expiresAt = now + 3600_000) {
  await setDoc(doc(as("mum"), `invites/${code}`), {familyId: F, role, expiresAt, createdBy: "mum"});
}

/** Child joins like joinWithCode(role: child). */
async function joinChild(uid, code) {
  const db = as(uid);
  await setDoc(doc(db, `families/${F}/members/${uid}`), {role: "child", name: uid, invite: code});
  await setDoc(doc(db, `families/${F}/children/${uid}`), {id: uid, name: uid, privacyMode: "live", points: 0});
  return db;
}

async function familyWithKids() {
  await createFamily();
  await invite("KIDAAA", "child");
  await joinChild("mia", "KIDAAA");
  await joinChild("leo", "KIDAAA");
}

describe("family setup", () => {
  test("parent creates a family and updates settings", async () => {
    const db = await createFamily();
    await assertSucceeds(setDoc(doc(db, `families/${F}`), {settings: {lowBatteryPct: 20}, tz: "Asia/Kolkata"}, {merge: true}));
  });

  test("someone can't add themselves as parent of another's family", async () => {
    await createFamily();
    await assertFails(setDoc(doc(as("eve"), `families/${F}/members/eve`), {role: "parent", name: "Eve"}));
  });

  test("strangers and signed-out users can't read the family", async () => {
    await createFamily();
    await assertFails(getDoc(doc(as("eve"), `families/${F}`)));
    await assertFails(getDoc(doc(anon(), `families/${F}`)));
  });
});

describe("invites", () => {
  test("a child code can only be used to join as a child", async () => {
    await createFamily();
    await invite("KIDAAA", "child");
    await assertSucceeds(getDoc(doc(as("mia"), "invites/KIDAAA")));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/members/mia`), {role: "parent", name: "Mia", invite: "KIDAAA"}));
    await assertSucceeds(setDoc(doc(as("mia"), `families/${F}/members/mia`), {role: "child", name: "Mia", invite: "KIDAAA"}));
  });

  test("a guardian code adds a second parent", async () => {
    await createFamily();
    await invite("DADAAA", "parent");
    await assertSucceeds(setDoc(doc(as("dad"), `families/${F}/members/dad`), {role: "parent", name: "Dad", invite: "DADAAA"}));
  });

  test("expired codes are rejected", async () => {
    await createFamily();
    await invite("OLDAAA", "child", now - 1000);
    await assertFails(setDoc(doc(as("mia"), `families/${F}/members/mia`), {role: "child", name: "Mia", invite: "OLDAAA"}));
  });

  test("codes can't be listed, and only parents create them", async () => {
    await createFamily();
    await assertFails(getDocs(collection(as("eve"), "invites")));
    await assertFails(setDoc(doc(as("eve"), "invites/EVEAAA"), {familyId: F, role: "parent", expiresAt: now + 1000, createdBy: "eve"}));
  });

  test("codes can't be made to last more than a day", async () => {
    await createFamily();
    await assertFails(setDoc(doc(as("mum"), "invites/LONGAA"), {familyId: F, role: "child", expiresAt: now + 7 * 86400_000, createdBy: "mum"}));
  });
});

describe("children", () => {
  test("child publishes presence, health and history", async () => {
    await familyWithKids();
    const mia = as("mia");
    await assertSucceeds(setDoc(doc(mia, `families/${F}/children/mia`),
      {lastFix: {lat: 1, lng: 2, acc: 5, at: now}, zoneId: "home"}, {merge: true}));
    await assertSucceeds(setDoc(doc(mia, `families/${F}/children/mia`), {health: {lastSeen: now}}, {merge: true}));
    await assertSucceeds(setDoc(doc(mia, `families/${F}/children/mia/history/h1`), {lat: 1, lng: 2, at: now, day: "2026-10-09"}));
  });

  test("child can pause and SOS but not change their own privacy mode or points", async () => {
    await familyWithKids();
    const mia = as("mia");
    await assertSucceeds(setDoc(doc(mia, `families/${F}/children/mia`), {pausedUntil: now + 1000, pauseReason: "party"}, {merge: true}));
    await assertSucceeds(setDoc(doc(mia, `families/${F}/children/mia`), {sosSince: now}, {merge: true}));
    await assertFails(setDoc(doc(mia, `families/${F}/children/mia`), {privacyMode: "checkInOnly"}, {merge: true}));
    await assertFails(setDoc(doc(mia, `families/${F}/children/mia`), {points: 9999}, {merge: true}));
  });

  test("parent changes privacy mode", async () => {
    await familyWithKids();
    await assertSucceeds(setDoc(doc(as("mum"), `families/${F}/children/leo`), {privacyMode: "placesOnly"}, {merge: true}));
  });

  test("siblings can't see each other's location, history or alerts", async () => {
    await familyWithKids();
    const leo = as("leo");
    await assertFails(getDoc(doc(leo, `families/${F}/children/mia`)));
    await assertFails(getDocs(collection(leo, `families/${F}/children/mia/history`)));
    await setDoc(doc(as("mia"), `families/${F}/alerts/a1`), {id: "a1", childId: "mia", type: "arrived", at: now});
    await assertFails(getDoc(doc(leo, `families/${F}/alerts/a1`)));
    await assertFails(getDocs(collection(leo, `families/${F}/children`)));
    await assertSucceeds(getDoc(doc(leo, `families/${F}/children/leo`)));
  });

  test("children can't read parents' push tokens", async () => {
    await familyWithKids();
    await assertFails(getDoc(doc(as("leo"), `families/${F}/members/mum`)));
    await assertSucceeds(getDoc(doc(as("mum"), `families/${F}/members/leo`)));
  });

  test("parent reads children, history (by day) and the alert feed", async () => {
    await familyWithKids();
    const mum = as("mum");
    await assertSucceeds(getDocs(collection(mum, `families/${F}/children`)));
    await assertSucceeds(getDocs(query(collection(mum, `families/${F}/children/mia/history`),
      where("day", "==", "2026-10-09"), orderBy("at"))));
    await assertSucceeds(getDocs(query(collection(mum, `families/${F}/alerts`), orderBy("at", "desc"), limit(100))));
  });
});

describe("alerts, commands, views, tasks", () => {
  test("a child can raise alerts only about themselves", async () => {
    await familyWithKids();
    await assertSucceeds(setDoc(doc(as("mia"), `families/${F}/alerts/a1`), {id: "a1", childId: "mia", type: "sos", at: now}));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/alerts/a2`), {id: "a2", childId: "leo", type: "sos", at: now}));
  });

  test("ring: parent sends, only the target child reads and acknowledges", async () => {
    await familyWithKids();
    await assertSucceeds(setDoc(doc(as("mum"), `families/${F}/commands/c1`), {id: "c1", childId: "mia", type: "ring", at: now}));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/commands/c2`), {id: "c2", childId: "leo", type: "ring", at: now}));
    await assertSucceeds(getDocs(query(collection(as("mia"), `families/${F}/commands`), where("childId", "==", "mia"))));
    await assertFails(getDocs(query(collection(as("leo"), `families/${F}/commands`), where("childId", "==", "mia"))));
    await assertFails(deleteDoc(doc(as("leo"), `families/${F}/commands/c1`)));
    await assertSucceeds(deleteDoc(doc(as("mia"), `families/${F}/commands/c1`)));
  });

  test("view log: parents write it, the child reads theirs, nobody erases it", async () => {
    await familyWithKids();
    await assertSucceeds(setDoc(doc(as("mum"), `families/${F}/views/v1`), {viewer: "Mum", at: now, childId: "mia"}));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/views/v2`), {viewer: "Mia", at: now, childId: "mia"}));
    await assertSucceeds(getDocs(query(collection(as("mia"), `families/${F}/views`),
      where("childId", "==", "mia"), orderBy("at", "desc"), limit(30))));
    await assertFails(deleteDoc(doc(as("mum"), `families/${F}/views/v1`)));
  });

  test("tasks: child marks done, only parents approve or change points", async () => {
    await familyWithKids();
    const t = {id: "t1", childId: "mia", title: "Bins", points: 10, status: "open"};
    await assertSucceeds(setDoc(doc(as("mum"), `families/${F}/tasks/t1`), t));
    await assertSucceeds(setDoc(doc(as("mia"), `families/${F}/tasks/t1`), {...t, status: "done"}));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/tasks/t1`), {...t, status: "approved"}));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/tasks/t1`), {...t, status: "done", points: 500}));
    await assertFails(setDoc(doc(as("leo"), `families/${F}/tasks/t1`), {...t, status: "done"}));
    await assertSucceeds(updateDoc(doc(as("mum"), `families/${F}/children/mia`), {points: 10}));
  });

  test("zones: everyone reads (children need them for alerts), parents write", async () => {
    await familyWithKids();
    await assertSucceeds(setDoc(doc(as("mum"), `families/${F}/zones/home`), {id: "home", name: "Home", lat: 1, lng: 2, radius: 100}));
    await assertSucceeds(getDocs(collection(as("mia"), `families/${F}/zones`)));
    await assertFails(setDoc(doc(as("mia"), `families/${F}/zones/home`), {id: "home", name: "Mine", lat: 1, lng: 2, radius: 5000}));
  });
});
