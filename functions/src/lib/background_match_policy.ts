export const MINUTE = 60000;
export const DAY = 86400000;
export const ALERT_GAP = 4 * 60 * MINUTE;
export const PAIR_GAP = 7 * DAY;
export const LOCATION_MAX_AGE = 30 * MINUTE;

export function keywords(value: unknown): Set<string> {
  const generic = new Set(['anything', 'everything', 'help', 'none', 'n/a', 'other']);
  return new Set((Array.isArray(value) ? value : []).filter((v): v is string => typeof v === 'string')
    .map(v => v.normalize('NFKC').trim().toLowerCase().replace(/\s+/g, ' '))
    .filter(v => v.length >= 2 && v.length <= 80 && !generic.has(v)).slice(0, 100));
}

export function reciprocalKeywords(a: Record<string, any>, b: Record<string, any>) {
  const wants = (p: Record<string, any>) => keywords(p.keywords?.['Searching For'] ?? p.SearchingFor);
  const offers = (p: Record<string, any>) => keywords(p.keywords?.['Can Provide'] ?? p.CanProvide);
  const intersect = (x: Set<string>, y: Set<string>) => [...x].filter(v => y.has(v)).sort();
  const forA = intersect(wants(a), offers(b));
  const forB = intersect(wants(b), offers(a));
  return {forA, forB, significant: forA.length >= 2 && forB.length >= 2,
    compatible: forA.length > 0 || forB.length > 0};
}

export function millis(value: any): number {
  return typeof value?.toMillis === 'function' ? value.toMillis() : 0;
}

export function liveLocation(p: Record<string, any>, now: number): boolean {
  const age = now - millis(p.locationAt);
  return p.enabled === true && Number.isFinite(p.latitude) && Math.abs(p.latitude) <= 90 &&
    Number.isFinite(p.longitude) && Math.abs(p.longitude) <= 180 &&
    Number.isFinite(p.accuracyMeters) && p.accuracyMeters >= 0 && p.accuracyMeters <= 300 &&
    age >= -MINUTE && age <= LOCATION_MAX_AGE && now - millis(p.receivedAt) >= -MINUTE &&
    now - millis(p.receivedAt) <= LOCATION_MAX_AGE;
}

export function miles(a: Record<string, any>, b: Record<string, any>): number {
  const r = Math.PI / 180;
  const h = Math.sin((b.latitude - a.latitude) * r / 2) ** 2 +
    Math.cos(a.latitude * r) * Math.cos(b.latitude * r) * Math.sin((b.longitude - a.longitude) * r / 2) ** 2;
  return 7917.6 * Math.asin(Math.sqrt(Math.min(1, h)));
}

export function quietNow(preferences: Record<string, any>, now: number): boolean {
  if (preferences.quietHoursEnabled === false) return false;
  // The current offset accompanies each location update, including DST changes.
  const offset = Math.max(-720, Math.min(840, Number(preferences.utcOffsetMinutes) || 0));
  const hour = new Date(now + offset * MINUTE).getUTCHours();
  return hour >= 22 || hour < 8;
}

export function alertAllowed(preferences: Record<string, any>, history: number[], pairAt: number, now: number): boolean {
  const limit = [1, 3, 6].includes(preferences.dailyAlertLimit) ? preferences.dailyAlertLimit : 3;
  const recent = history.filter(t => Number.isFinite(t) && now - t < DAY);
  return preferences.enabled === true && preferences.notificationsEnabled === true &&
    !quietNow(preferences, now) && recent.length < limit &&
    recent.every(t => now - t >= ALERT_GAP) && (!pairAt || now - pairAt >= PAIR_GAP);
}

export function matchesCriteria(settings: Record<string, any>, peer: Record<string, any>, fit: ReturnType<typeof reciprocalKeywords>): boolean {
  if (settings.businessOnly === true && peer.isBusiness !== true) return false;
  if (settings.businessOnly === true && settings.immediateOnly === true &&
      !(typeof peer.availabilityMinutes === 'number' && peer.availabilityMinutes <= 0)) return false;
  const ages: Record<string, [number, number]> = {age18To24: [18, 24], age25To34: [25, 34],
    age35To44: [35, 44], age45To54: [45, 54], age55Plus: [55, 120]};
  const range = ages[settings.ageBracket];
  if (range && !(peer.ageYears >= range[0] && peer.ageYears <= range[1])) return false;
  if (settings.keywordMode === 'reciprocalOpposite' && !(fit.forA.length && fit.forB.length)) return false;
  if (settings.keywordMode === 'keywordChain' && new Set([...fit.forA, ...fit.forB]).size < 2) return false;
  return fit.compatible;
}
