const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function landing(search) {
  const source = readFileSync(path.join(__dirname, '../../referral.html'), 'utf8');
  const script = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)].at(-1)[1];
  const elements = new Map();
  const copied = [];
  const document = {getElementById(id) {
    if (!elements.has(id)) elements.set(id, {hidden: true, textContent: '', href: '', listeners: {},
      addEventListener(type, listener) {this.listeners[type] = listener;}});
    return elements.get(id);
  }};
  vm.runInNewContext(script, {URL, URLSearchParams, location: {search}, document,
    navigator: {clipboard: {writeText: async text => copied.push(text)}}});
  return {get: id => document.getElementById(id), copied};
}

test('in-person token survives installing, reopening Prox and either platform download', async () => {
  const token = 'T-ABCDEF123456789012';
  const page = landing(`?t=${token}&party=1&inperson=1`);
  assert.equal(page.get('invitation').hidden, false);
  for (const id of ['open', 'android', 'ios']) {
    const link = new URL(page.get(id).href);
    assert.equal(link.searchParams.get('t'), token);
    assert.equal(link.searchParams.get('party'), '1');
    assert.equal(link.searchParams.get('inperson'), '1');
  }
  assert.equal(new URL(page.get('ios').href).searchParams.get('platform'), 'ios');
  assert.match(page.get('instructions').textContent, /still together/);
  await page.get('copy').listeners.click();
  assert.equal(new URL(page.copied[0]).hostname, 'prox-us.com');
  assert.equal(new URL(page.copied[0]).searchParams.get('t'), token);
});

test('ordinary referral links and founding tester codes preserve their attribution without Party intent', () => {
  for (const code of ['INV123', 'PROX-P-ABCDEF123456']) {
    const page = landing(`?code=${code}&ref=friend&party=1`);
    const link = new URL(page.get('open').href);
    assert.equal(link.searchParams.get('code'), code);
    assert.equal(link.searchParams.get('ref'), 'friend');
    assert.equal(link.searchParams.has('party'), false);
  }
});

test('malformed tokens and injected code content expose no app or download link', () => {
  for (const query of ['?t=invalid&code=INV123', '?code=%3Cscript%3E', '']) {
    const page = landing(query);
    assert.equal(page.get('invalid').hidden, false);
    assert.equal(page.get('open').href, '');
    assert.equal(page.get('android').href, '');
  }
});

test('root landing routes invitation signals to the invitation page and leaves marketing visits intact', () => {
  const source = readFileSync(path.join(__dirname, '../../index.html'), 'utf8');
  const script = [...source.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
  for (const search of ['?t=T-ABCDEF123456789012&party=1', '?code=INV123', '?utm_campaign=launch']) {
    const redirects = [];
    vm.runInNewContext(script, {URLSearchParams, location: {search, replace: to => redirects.push(to)}});
    assert.deepEqual(redirects, search.includes('utm_campaign') ? [] : ['referral.html' + search]);
  }
});
