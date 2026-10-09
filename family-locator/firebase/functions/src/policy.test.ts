import {test} from "node:test";
import assert from "node:assert/strict";
import {decideDelivery, digestSummary, isStale, localClock, windowContains} from "./policy";

// 2026-10-05 is a Monday. Build UTC instants for local times at UTC+2.
const tz = 120;
const at = (day: number, h: number, m = 0) => Date.UTC(2026, 9, day, h, m) - tz * 60_000;
const local = (day: number, h: number) => new Date(Date.UTC(2026, 9, day, h));

const quiet = {days: [1, 2, 3, 4, 5, 6, 7], start: 22 * 60, end: 7 * 60};
const school = {days: [1, 2, 3, 4, 5], start: 7 * 60, end: 17 * 60};

test("overnight windows wrap past midnight", () => {
  const fri = {days: [5], start: 22 * 60, end: 7 * 60};
  assert.equal(windowContains(fri, local(9, 23)), true); // Fri 23:00
  assert.equal(windowContains(fri, local(10, 6)), true); // Sat 06:00
  assert.equal(windowContains(fri, local(9, 6)), false); // Fri 06:00
});

test("delivery matches the app's policy", () => {
  const base = {id: "a", childId: "c", message: "m"};
  assert.equal(decideDelivery({...base, type: "sos", at: at(5, 23)}, {quietHours: quiet}, tz), "now");
  assert.equal(decideDelivery({...base, type: "lowBattery", at: at(5, 23)}, {quietHours: quiet}, tz), "digest");
  assert.equal(decideDelivery({...base, type: "arrived", at: at(10, 10)}, {}, tz, school), "feedOnly");
  assert.equal(decideDelivery({...base, type: "arrived", at: at(5, 8)}, {quietHours: quiet}, tz, school), "now");
});

test("stale detection ignores paused and never-seen phones", () => {
  const now = Date.UTC(2026, 9, 5, 12);
  const old = now - 45 * 60_000;
  assert.equal(isStale({health: {lastSeen: old}}, now, 30), true);
  assert.equal(isStale({health: {lastSeen: old}, pausedUntil: now + 1}, now, 30), false);
  assert.equal(isStale({}, now, 30), false);
  assert.equal(isStale({health: {lastSeen: old}, lastFix: {at: now - 60_000}}, now, 30), false);
});

test("digest summary", () => {
  const s = digestSummary([{id: "1", childId: "c", type: "lowBattery", at: at(5, 23, 5), message: "Mia's phone is at 14%"}], tz);
  assert.equal(s, "1 update during quiet hours:\n23:05 Mia's phone is at 14%");
});

test("IANA zones follow daylight saving", () => {
  // London: 12:00 UTC is 13:00 in summer (BST) and 12:00 in winter (GMT).
  assert.equal(localClock(Date.UTC(2026, 6, 1, 12), "Europe/London").getUTCHours(), 13);
  assert.equal(localClock(Date.UTC(2026, 11, 1, 12), "Europe/London").getUTCHours(), 12);
  // Kolkata is +05:30 all year; 23:00 UTC Sunday is Monday 04:30 locally.
  const k = localClock(Date.UTC(2026, 9, 4, 23), "Asia/Kolkata");
  assert.deepEqual([k.getUTCDay(), k.getUTCHours(), k.getUTCMinutes()], [1, 4, 30]);
  // Unknown names fall back to UTC instead of throwing.
  assert.equal(localClock(Date.UTC(2026, 0, 1, 9), "Not/AZone").getUTCHours(), 9);
});
