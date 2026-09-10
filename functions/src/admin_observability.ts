import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import { runActiveModePolicySweep } from "./lib/active_mode";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();

type AdminToken = {
  uid: string;
  isAdmin: boolean;
};

type AdminHttpErrorCode =
  | "unauthenticated"
  | "permission-denied"
  | "deadline-exceeded"
  | "internal";

class AdminHttpError extends Error {
  public readonly code: AdminHttpErrorCode;
  public readonly status: number;

  constructor(code: AdminHttpErrorCode, message: string, status: number) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

async function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  operation: string,
): Promise<T> {
  return Promise.race<T>([
    promise,
    new Promise<T>((_, reject) => {
      setTimeout(() => {
        reject(new AdminHttpError(
          "deadline-exceeded",
          `${operation} timed out.`,
          504,
        ));
      }, ms);
    }),
  ]);
}

function bearerToken(headerValue: string | undefined): string {
  if (!headerValue) return "";
  const m = headerValue.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : "";
}

async function verifyAdmin(req: functions.https.Request): Promise<AdminToken> {
  const token = bearerToken(req.get("authorization"));
  if (!token) {
    throw new AdminHttpError("unauthenticated", "Missing bearer token.", 401);
  }

  const decoded = await admin.auth().verifyIdToken(token);
  const claims = decoded as unknown as Record<string, unknown>;
  const isAdmin = claims["admin"] === true;
  if (!isAdmin) {
    throw new AdminHttpError("permission-denied", "Admin claim required.", 403);
  }

  return { uid: decoded.uid, isAdmin };
}

export const getActiveModeSweepHealth = functions.https.onRequest(async (req, res) => {
  if (req.method !== "GET") {
    res.status(405).json({ ok: false, error: "method-not-allowed" });
    return;
  }

  try {
    const auth = await verifyAdmin(req);
    const snap = await withTimeout(
      db.collection("dashboard").doc("activeModePolicySweep").get(),
      8000,
      "Sweep health read",
    );
    const data = (snap.data() || {}) as Record<string, unknown>;

    res.status(200).json({
      ok: true,
      viewerUid: auth.uid,
      data,
    });
  } catch (err) {
    if (err instanceof AdminHttpError) {
      res.status(err.status).json({ ok: false, error: err.code, message: err.message });
      return;
    }

    functions.logger.error("getActiveModeSweepHealth failed", err);
    res.status(500).json({ ok: false, error: "internal" });
  }
});

export const runActiveModeSweepNow = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).json({ ok: false, error: "method-not-allowed" });
    return;
  }

  try {
    const auth = await verifyAdmin(req);
    const summary = await withTimeout(
      runActiveModePolicySweep({
        source: "admin-endpoint",
        requestedByUid: auth.uid,
      }),
      20000,
      "Manual sweep",
    );

    res.status(200).json({
      ok: true,
      summary,
    });
  } catch (err) {
    if (err instanceof AdminHttpError) {
      res.status(err.status).json({ ok: false, error: err.code, message: err.message });
      return;
    }

    functions.logger.error("runActiveModeSweepNow failed", err);
    res.status(500).json({ ok: false, error: "internal" });
  }
});
