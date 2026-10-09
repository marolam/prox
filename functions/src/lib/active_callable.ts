import * as admin from 'firebase-admin';
import {
  CallableFunction, CallableOptions, CallableRequest, CallableResponse,
  HttpsError, onCall as firebaseOnCall, onRequest,
} from 'firebase-functions/v2/https';

export {HttpsError, onRequest};
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
export const CALLS_PER_MINUTE = 120;

export async function assertAccountAccess(uid: string, recovery = false): Promise<void> {
  const [enforcement, deletion] = await db.getAll(
    db.doc(`accountEnforcements/${uid}`), db.doc(`accountDeletions/${uid}`));
  if (deletion.exists || enforcement.data()?.status === 'deleted') {
    throw new HttpsError('permission-denied', 'This account is being deleted.');
  }
  if (!recovery && enforcement.exists && enforcement.data()?.status !== 'active') {
    throw new HttpsError('permission-denied', 'This account is suspended. Contact support to appeal.');
  }
}

export async function claimCallableRequest(uid: string, recovery = false): Promise<void> {
  await db.runTransaction(async tx => {
    const [enforcement, deletion, quota, user] = await tx.getAll(
      db.doc(`accountEnforcements/${uid}`), db.doc(`accountDeletions/${uid}`),
      db.doc(`functionRateLimits/${uid}`), db.doc(`users/${uid}`));
    if (deletion.exists || enforcement.data()?.status === 'deleted') {
      throw new HttpsError('permission-denied', 'This account is unavailable because it is being deleted.');
    }
    if (!recovery && (enforcement.exists && enforcement.data()?.status !== 'active' ||
          user.data()?.disabled === true || user.data()?.banned === true)) {
      throw new HttpsError('permission-denied', 'This account is unavailable or restricted. Contact support.');
    }
    if (!recovery && user.data()?.referralTrustRequired === true && user.data()?.referralInPersonVerified !== true) {
      throw new HttpsError('failed-precondition', 'Verify your referrer QR in person before using this feature.');
    }
    const minute = Math.floor(Date.now() / 60000);
    const count = quota.data()?.minute === minute ? Number(quota.data()?.count || 0) : 0;
    if (count >= CALLS_PER_MINUTE) throw new HttpsError('resource-exhausted', 'Too many requests. Wait a minute and try again.');
    tx.set(quota.ref, {minute, count: count + 1,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 86400000)});
  });
}

type Handler<T, R, S> = (request: CallableRequest<T>, response?: CallableResponse<S>) => R;

function guardedCall<T, R, S>(options: CallableOptions<T>, handler: Handler<T, R, S>, recovery = false):
    CallableFunction<T, Promise<Awaited<R>>, S> {
  const appCheck = process.env.PROX_ENFORCE_APP_CHECK;
  if (appCheck !== undefined && appCheck !== 'true' && appCheck !== 'false') {
    throw new Error('PROX_ENFORCE_APP_CHECK must be true or false.');
  }
  return firebaseOnCall<T, Promise<Awaited<R>>, S>(
    {...options, enforceAppCheck: appCheck === 'true' || options.enforceAppCheck === true},
    async (request, response): Promise<Awaited<R>> => {
      if (request.auth) await claimCallableRequest(request.auth.uid, recovery);
      return await handler(request, response);
    });
}

export function onCall<T = any, R = any, S = unknown>(options: CallableOptions<T>, handler: Handler<T, R, S>): CallableFunction<T, Promise<Awaited<R>>, S>;
export function onCall<T = any, R = any, S = unknown>(handler: Handler<T, R, S>): CallableFunction<T, Promise<Awaited<R>>, S>;
export function onCall<T = any, R = any, S = unknown>(
  options: CallableOptions<T> | Handler<T, R, S>, handler?: Handler<T, R, S>,
): CallableFunction<T, Promise<Awaited<R>>, S> {
  if (typeof options === 'function') return guardedCall({}, options);
  if (!handler) throw new Error('A callable handler is required.');
  return guardedCall(options, handler);
}

export function onRecoveryCall<T = any, R = any, S = unknown>(
  options: CallableOptions<T>, handler: Handler<T, R, S>,
): CallableFunction<T, Promise<Awaited<R>>, S> {
  return guardedCall(options, handler, true);
}
