import {DAY, millis, miles, MINUTE} from './background_match_policy';

export const LOCAL_ENROLLMENT_MAX_AGE = 30 * DAY;
export const PUBLIC_RECEIPT_MAX_AGE = 15 * MINUTE;
export const DEFAULT_PUBLIC_DISCOVERY_CONFIG = {minimumUsers: 1000, radiusMiles: 10, activeWithinDays: 30};
export type DiscoveryScope = 'partyOnly' | 'tree' | 'public';
export type Relationship = 'direct' | 'tree' | 'none';

export function discoveryScope(value: unknown): DiscoveryScope {
  if (value === 'partyOnly') return 'partyOnly';
  if (value === 'public' || value === 'all') return 'public';
  return 'tree';
}

/** Provisional rollout defaults are configurable; explicitly invalid or disabled configuration fails closed. */
export function publicDiscoveryConfig(value: Record<string, any> | undefined) {
  if (!value) return {...DEFAULT_PUBLIC_DISCOVERY_CONFIG};
  const activeWithinDays = value.activeWithinDays ?? 30;
  if (!Number.isInteger(value.minimumUsers) || value.minimumUsers < 2 || value.minimumUsers > 5000 ||
      !Number.isFinite(value.radiusMiles) || value.radiusMiles < .1 || value.radiusMiles > 50 || value.enabled === false ||
      !Number.isInteger(activeWithinDays) || activeWithinDays < 1 || activeWithinDays > 30) return null;
  return {minimumUsers: value.minimumUsers as number, radiusMiles: value.radiusMiles as number, activeWithinDays: activeWithinDays as number};
}
export function publicDiscoveryFingerprint(config: ReturnType<typeof publicDiscoveryConfig>): string {
  return config ? `${config.minimumUsers}:${config.radiusMiles}:${config.activeWithinDays}` : 'locked';
}

export function activeEnrolledAccount(value: Record<string, any> | undefined): boolean {
  return !!value && value.disabled !== true && value.banned !== true &&
    (value.referralTrustRequired !== true || value.referralInPersonVerified === true) &&
    !['deleted', 'deactivated', 'disabled', 'banned'].includes(value.status);
}

export function recentEnrollmentLocation(value: Record<string, any>, now: number, activeWithinDays = 30): boolean {
  const age = now - millis(value.lastSeenAt);
  return Number.isFinite(value.latitude) && Math.abs(value.latitude) <= 90 &&
    Number.isFinite(value.longitude) && Math.abs(value.longitude) <= 180 &&
    age >= -MINUTE && age <= activeWithinDays * DAY;
}

/** Both projections and the server consent receipt must describe the same proven connection. */
export function trustedPartyEdge(a: string, b: string, forward: Record<string, any>, reverse: Record<string, any>,
  receipt: Record<string, any>): boolean {
  return a !== b && forward.uid === b && reverse.uid === a && forward.mutual === true && reverse.mutual === true &&
    forward.metInPerson === true && reverse.metInPerson === true &&
    typeof forward.connectionId === 'string' && forward.connectionId.length > 0 && forward.connectionId === reverse.connectionId &&
    receipt.status === 'connected' && Array.isArray(receipt.members) && receipt.members.length === 2 &&
    receipt.members.includes(a) && receipt.members.includes(b) && receipt.decisions?.[a] === 'add' && receipt.decisions?.[b] === 'add' &&
    ['completedMeetup', 'inPersonCode', 'referralQr'].includes(receipt.proof?.kind);
}

export function scopeAllows(scope: unknown, unlocked: boolean, relationship: Relationship): boolean {
  const selected = discoveryScope(scope);
  if (selected === 'partyOnly') return relationship === 'direct';
  if (selected === 'public' && unlocked) return true;
  return relationship === 'direct' || relationship === 'tree';
}

export function reciprocalScopeAllows(a: Record<string, any>, b: Record<string, any>, relationship: Relationship): boolean {
  return scopeAllows(a.partyScope, a.publicUnlocked === true, relationship) &&
    scopeAllows(b.partyScope, b.publicUnlocked === true, relationship);
}

/** A receipt for another location or an old density check cannot authorize public background matching. */
export function currentPublicReceipt(receipt: Record<string, any>, location: Record<string, any>, now: number): boolean {
  return receipt.publicUnlocked === true && now - millis(receipt.checkedAt) >= -MINUTE &&
    now - millis(receipt.checkedAt) <= PUBLIC_RECEIPT_MAX_AGE &&
    Number.isFinite(receipt.latitude) && Number.isFinite(receipt.longitude) &&
    miles(receipt, location) <= .1;
}
