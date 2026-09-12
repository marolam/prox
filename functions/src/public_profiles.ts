import * as admin from 'firebase-admin';
import {onDocumentWritten} from 'firebase-functions/v2/firestore';
import {isDeepStrictEqual} from 'node:util';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/** Firestore map order is immaterial; array order and Timestamp precision are not. */
export function publicProfilesEqual(previous: unknown, next: unknown): boolean {
  return isDeepStrictEqual(previous, next);
}

/** Explicit projection: never copy arbitrary account maps into discovery data. */
export function publicProfile(uid: string, account: Record<string, any>, settings: Record<string, any> = {}): Record<string, unknown> {
  const text = (value: unknown, max = 2000): string => typeof value === 'string' ? value.trim().slice(0, max) : '';
  const list = (value: unknown): string[] => Array.isArray(value)
    ? [...new Set(value.filter(item => typeof item === 'string').map(item => text(item, 80)).filter(Boolean))].slice(0, 100) : [];
  const groups = account.keywords || account.keywordGroups || {};
  const wants = list(groups['Searching For'] || groups.searchingFor || account.SearchingFor || account['Searching For']);
  const offers = list(groups['Can Provide'] || groups.canProvide || account.CanProvide || account['Can Provide']);
  const visible = list(groups['Visible Inventory'] || account.keywordWorkspace?.visibleInventory);
  const name = text(account.displayName || account.name || account.alias, 120);
  const photo = text(account.photoUrl || account.photoURL || account.selfieUrl, 2000);
  const age = Number(account.ageYears || account.age);
  const peerSetting = (key: string): string => text(settings[key] || account[key] || account.matching?.[key] || account.matchingSettings?.[key] || account.settings?.matching?.[key], 40);
  const modeKind = peerSetting('modeKind');
  const normalMode = peerSetting('normalMode');
  const listenRole = peerSetting('listenRole');
  const business = account.businessEnabled === true || account.isBusiness === true || account.businessMode === true;
  return {
    uid, displayName: name, name, alias: name, photoUrl: photo, photoURL: photo, selfieUrl: photo,
    headline: text(account.headline), bio: text(account.bio || account.about || account.headline), about: text(account.bio || account.about || account.headline),
    searchingText: text(account.searchingText), providingText: text(account.providingText),
    businessEnabled: business, isBusiness: business, businessMode: business,
    ...(modeKind ? {modeKind} : {}), ...(normalMode ? {normalMode} : {}), ...(listenRole ? {listenRole} : {}),
    availabilityMinutes: Number.isFinite(account.availabilityMinutes) ? Math.max(0, Math.min(1440, account.availabilityMinutes)) : null,
    ...(Number.isInteger(age) && age >= 13 && age <= 120 ? {ageYears: age, age} : {}),
    SearchingFor: wants, CanProvide: offers,
    keywords: {'Searching For': wants, 'Can Provide': offers, 'Visible Inventory': visible},
    keywordGroups: {'Searching For': wants, 'Can Provide': offers, 'Visible Inventory': visible},
    activeKeywords: [...new Set([...wants, ...offers].map(value => value.toLowerCase()))].sort(),
    busyInMeetup: account.interactionLock?.busyInMeetup === true,
    interactionLock: {busyInMeetup: account.interactionLock?.busyInMeetup === true},
    ...(account.updatedAt instanceof admin.firestore.Timestamp ? {updatedAt: account.updatedAt} : {}),
    searchKey: name.toLowerCase(),
    schemaVersion: 1,
  };
}

export async function syncPublicProfile(uid: string): Promise<void> {
  const target = db.doc(`publicProfiles/${uid}`);
  await db.runTransaction(async tx => {
    const [account, previous, deletion, settings] = await tx.getAll(db.doc(`users/${uid}`), target, db.doc(`accountDeletions/${uid}`), db.doc(`users/${uid}/settings/matching`));
    if (!account.exists || deletion.exists) {
      if (previous.exists) tx.delete(target);
      return;
    }
    const next = publicProfile(uid, account.data() || {}, settings.data() || {});
    // Replacement removes unknown fields from old projections as well.
    if (!publicProfilesEqual(previous.data(), next)) tx.set(target, next);
  });
}

export const onPublicProfileProjection = onDocumentWritten({document: 'users/{uid}', retry: true}, async event => {
  await syncPublicProfile(event.params.uid);
});

export const onPublicMatchingProjection = onDocumentWritten({document: 'users/{uid}/settings/matching', retry: true}, async event => {
  await syncPublicProfile(event.params.uid);
});
