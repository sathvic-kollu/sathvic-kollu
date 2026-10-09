// Server-side mirror of lib/core/alert_policy.dart and the TimeWindow
// logic in lib/core/models.dart. Keep the two in step.

export interface TimeWindow {
  days: number[]; // ISO weekdays, Monday = 1
  start: number; // minutes after midnight
  end: number;
}

export interface Settings {
  quietHours?: TimeWindow | null;
  lowBatteryPct?: number;
  maxPauseMinutes?: number;
  staleAfterMinutes?: number;
}

export interface Alert {
  id: string;
  childId: string;
  type: string;
  at: number;
  message: string;
  zoneId?: string | null;
  urgent?: boolean;
}

export const URGENT = new Set(["sos", "trackingOff", "permissionLost"]);

/** Wall-clock time in the family's zone, as a Date whose UTC fields are local. */
export function localClock(epochMs: number, tzOffsetMinutes: number): Date {
  return new Date(epochMs + tzOffsetMinutes * 60_000);
}

function isoWeekday(d: Date): number {
  const w = d.getUTCDay();
  return w === 0 ? 7 : w;
}

export function windowContains(w: TimeWindow, local: Date): boolean {
  const minute = local.getUTCHours() * 60 + local.getUTCMinutes();
  const day = isoWeekday(local);
  const days = new Set(w.days);
  if (w.start <= w.end) return days.has(day) && minute >= w.start && minute < w.end;
  if (minute >= w.start) return days.has(day);
  if (minute < w.end) return days.has(day === 1 ? 7 : day - 1);
  return false;
}

export type Delivery = "now" | "digest" | "feedOnly";

export function decideDelivery(
  alert: Alert,
  settings: Settings,
  tzOffsetMinutes: number,
  zoneWindow?: TimeWindow | null,
): Delivery {
  if (URGENT.has(alert.type)) return "now";
  const local = localClock(alert.at, tzOffsetMinutes);
  if ((alert.type === "arrived" || alert.type === "left") && zoneWindow && !windowContains(zoneWindow, local)) {
    return "feedOnly";
  }
  if (settings.quietHours && windowContains(settings.quietHours, local)) return "digest";
  return "now";
}

export interface ChildDoc {
  pausedUntil?: number | null;
  lastFix?: { at?: number } | null;
  health?: { lastSeen?: number } | null;
}

/** Newest sign of life from the child's phone, or null if none yet. */
export function lastSeen(child: ChildDoc): number | null {
  const a = child.lastFix?.at ?? null;
  const b = child.health?.lastSeen ?? null;
  if (a === null) return b;
  if (b === null) return a;
  return Math.max(a, b);
}

export function isStale(child: ChildDoc, now: number, staleAfterMinutes: number): boolean {
  if (child.pausedUntil && child.pausedUntil > now) return false;
  const seen = lastSeen(child);
  if (seen === null) return false; // Never set up; nothing has "stopped".
  return now - seen > staleAfterMinutes * 60_000;
}

export function digestSummary(held: Alert[], tzOffsetMinutes: number): string {
  const sorted = [...held].sort((a, b) => a.at - b.at);
  const fmt = (ms: number) => {
    const d = localClock(ms, tzOffsetMinutes);
    return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
  };
  const lines = sorted.slice(0, 6).map((a) => `${fmt(a.at)} ${a.message}`);
  const more = sorted.length - lines.length;
  return [
    `${held.length} update${held.length === 1 ? "" : "s"} during quiet hours:`,
    ...lines,
    ...(more > 0 ? [`…and ${more} more`] : []),
  ].join("\n");
}
