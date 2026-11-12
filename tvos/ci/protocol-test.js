// Checks that the Apple TV app's way of talking to Supabase works with the
// phones. "TV" below sends the exact raw messages RealtimeClient.swift sends
// and runs the same JS files the app bundles. "Phone" uses supabase-js the
// way the live play page does.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { createClient } = require('@supabase/supabase-js');

const APP = path.join(__dirname, '..', 'BuzzworthyTV');
const cfg = fs.readFileSync(path.join(APP, 'Config.swift'), 'utf8');
const URL_ = cfg.match(/supabaseURL = "([^"]+)"/)[1];
const KEY = cfg.match(/supabaseKey = "([^"]+)"/)[1];

let ref = 0;
const nextRef = () => String(++ref);
const ws = new WebSocket(`${URL_.replace('https://', 'wss://')}/realtime/v1/websocket?apikey=${KEY}&vsn=1.0.0`);
const joinRefs = {};
const joined = {};
const queue = {};
function join(name) {
  if (joinRefs[name]) return;
  const r = nextRef();
  joinRefs[name] = r;
  ws.send(`{"topic":"realtime:${name}","event":"phx_join","payload":{"config":{"broadcast":{"self":false,"ack":false},"presence":{"key":""},"postgres_changes":[],"private":false},"access_token":"${KEY}"},"ref":"${r}","join_ref":"${r}"}`);
}
function send(name, event, json) {
  join(name);
  const msg = () => `{"topic":"realtime:${name}","event":"broadcast","payload":{"type":"broadcast","event":"${event}","payload":${json}},"ref":"${nextRef()}","join_ref":"${joinRefs[name]}"}`;
  if (joined[name]) ws.send(msg()); else (queue[name] = queue[name] || []).push(msg);
}

let tvState = null;
const timers = {};
const native = {
  send: (c, e, j) => send(c, e, j),
  state: (j) => { tvState = JSON.parse(j); },
  schedule: (id, ms, rep) => { timers[id] = (rep ? setInterval : setTimeout)(() => ctx.__fire(id, rep), ms); },
  cancel: (id) => { clearTimeout(timers[id]); clearInterval(timers[id]); },
  log: console.log,
};
const ctx = vm.createContext({ __native: native, JSON, Math, Date });
for (const f of ['shim', 'judge', 'game', 'rules', 'hub']) vm.runInContext(fs.readFileSync(path.join(APP, 'Engine', f + '.js'), 'utf8'), ctx);
const packs = '[' + ['default', 'general', 'movies', 'nineties', 'sports']
  .map((id) => `{"id":"${id}","data":${fs.readFileSync(path.join(APP, 'Questions', id + '.json'), 'utf8')}}`).join(',') + ']';

function fail(msg) { console.error('FAIL:', msg); process.exit(1); }
setTimeout(() => fail('timed out'), 30000);

ws.onerror = (e) => fail('websocket error ' + (e.message || ''));
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  const name = m.topic.replace(/^realtime:/, '');
  if (m.event === 'phx_reply' && joinRefs[name] === m.ref) {
    if (m.payload.status !== 'ok') fail('join refused ' + JSON.stringify(m.payload));
    joined[name] = true;
    (queue[name] || []).splice(0).forEach((f) => ws.send(f()));
    if (name === `bw:${code}`) startPhone();
  }
  if (m.event === 'broadcast' && name === `bw:${code}`) {
    ctx.Hub.onMessage(m.payload.event, JSON.stringify(m.payload.payload || {}));
  }
};

let code = null;
ws.onopen = () => {
  code = vm.runInContext(`Hub.create(${JSON.stringify(packs)})`, ctx);
  console.log('TV room code', code);
  join(`bw:${code}`);
};

async function startPhone() {
  const sb = createClient(URL_, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const pid = 'abcdef0123456789';
  const mine = sb.channel(`bw:${code}:${pid}`, { config: { broadcast: { self: false, ack: false } } });
  let gotReply = false;
  mine.on('broadcast', { event: 'reply' }, (m) => { console.log('phone got reply', JSON.stringify(m.payload)); gotReply = m.payload.result && m.payload.result.code === code; });
  mine.on('broadcast', { event: 'state' }, (m) => {
    const s = m.payload;
    console.log('phone got state: phase', s.phase, 'players', s.players.map((p) => p.name).join(','));
    if (gotReply && s.me && tvState && tvState.players.some((p) => p.name === 'CI Phone' && p.connected)) {
      console.log('PASS: phone joined the Apple TV room and both sides see each other');
      process.exit(0);
    }
  });
  await new Promise((r) => mine.subscribe((st) => st === 'SUBSCRIBED' && r()));
  const main = sb.channel(`bw:${code}`, { config: { broadcast: { self: false, ack: false } } });
  await new Promise((r) => main.subscribe((st) => st === 'SUBSCRIBED' && r()));
  await main.send({ type: 'broadcast', event: 'join', payload: { pid, name: 'CI Phone', host: false, reqId: 'r1' } });
}
