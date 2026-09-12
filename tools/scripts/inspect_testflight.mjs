// Read-only App Store Connect discovery using the key already held in CI.
import { createPrivateKey, sign } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export function tokenFor(env, now = Math.floor(Date.now() / 1000)) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({ alg: 'ES256', kid: env.APP_STORE_CONNECT_API_KEY_ID, typ: 'JWT' });
  const payload = encode({ iss: env.APP_STORE_CONNECT_ISSUER_ID, iat: now, exp: now + 300, aud: 'appstoreconnect-v1' });
  const key = createPrivateKey(Buffer.from(env.APP_STORE_CONNECT_API_KEY_P8_BASE64, 'base64'));
  const message = `${header}.${payload}`;
  const signature = sign('sha256', Buffer.from(message), { key, dsaEncoding: 'ieee-p1363' });
  return `${message}.${signature.toString('base64url')}`;
}

export async function inspect(apiGet, bundleId = 'com.prox-us.prox') {
  const apps = await apiGet(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&fields[apps]=bundleId,name&limit=2`);
  if (apps.data.length !== 1 || apps.data[0].attributes.bundleId !== bundleId) {
    throw new Error('Expected exactly one matching App Store Connect app');
  }
  const app = apps.data[0];
  let path = `/v1/apps/${app.id}/betaGroups?fields[betaGroups]=name,isInternalGroup,publicLinkEnabled,publicLink&limit=200`;
  const groups = [];
  for (let page = 0; path && page < 10; page++) {
    const response = await apiGet(path);
    for (const group of response.data) {
      const a = group.attributes;
      groups.push({ name: a.name, internal: a.isInternalGroup, publicLinkEnabled: a.publicLinkEnabled,
        publicLink: a.publicLinkEnabled && /^https:\/\/testflight\.apple\.com\/join\/[A-Za-z0-9]+$/.test(a.publicLink ?? '') ? a.publicLink : null });
    }
    path = response.links?.next;
  }
  if (path) throw new Error('Too many beta-group pages; inspection incomplete');
  return { appId: app.id, bundleId, groups };
}

async function main() {
  for (const key of ['APP_STORE_CONNECT_API_KEY_ID', 'APP_STORE_CONNECT_ISSUER_ID', 'APP_STORE_CONNECT_API_KEY_P8_BASE64']) {
    if (!process.env[key]) throw new Error(`Missing CI secret: ${key}`);
  }
  const token = tokenFor(process.env);
  const apiGet = async path => {
    const url = new URL(path, 'https://api.appstoreconnect.apple.com');
    if (url.origin !== 'https://api.appstoreconnect.apple.com' || url.username || url.password) {
      throw new Error('Unexpected App Store Connect API origin');
    }
    const response = await fetch(url, { method: 'GET', redirect: 'error',
      headers: { Authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`App Store Connect lookup failed: HTTP ${response.status}`);
    return response.json();
  };
  console.log(JSON.stringify(await inspect(apiGet), null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
