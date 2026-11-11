// Plays part of a game against the Apple TV app running in the simulator,
// taking screenshots along the way. Usage: node drive.js ROOMCODE OUTDIR
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { createClient } = require('@supabase/supabase-js');

const cfg = fs.readFileSync(path.join(__dirname, '..', 'BuzzworthyTV', 'Config.swift'), 'utf8');
const URL_ = cfg.match(/supabaseURL = "([^"]+)"/)[1];
const KEY = cfg.match(/supabaseKey = "([^"]+)"/)[1];
const [code, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const shot = (name) => { execSync(`xcrun simctl io booted screenshot "${path.join(out, name + '.png')}"`); console.log('shot', name); };
const hex = () => [...Array(16)].map(() => '0123456789abcdef'[Math.floor(Math.random() * 16)]).join('');

async function phone(name) {
  const sb = createClient(URL_, KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const pid = hex();
  const p = { pid, name, state: null, pending: new Map() };
  const mine = sb.channel(`bw:${code}:${pid}`, { config: { broadcast: { self: false, ack: false } } });
  mine.on('broadcast', { event: 'state' }, (m) => { p.state = m.payload; });
  mine.on('broadcast', { event: 'reply' }, (m) => { const f = p.pending.get(m.payload.reqId); f && f(m.payload.result); });
  await new Promise((r) => mine.subscribe((s) => s === 'SUBSCRIBED' && r()));
  const main = sb.channel(`bw:${code}`, { config: { broadcast: { self: false, ack: false } } });
  await new Promise((r) => main.subscribe((s) => s === 'SUBSCRIBED' && r()));
  p.rpc = (event, payload) => new Promise((resolve) => {
    const reqId = hex().slice(0, 12);
    p.pending.set(reqId, resolve);
    setTimeout(() => resolve({ error: 'timeout' }), 6000);
    main.send({ type: 'broadcast', event, payload: { ...payload, pid, reqId } });
  });
  p.act = (body) => p.rpc('act', { body });
  setInterval(() => main.send({ type: 'broadcast', event: 'hb', payload: { pid } }), 4000);
  console.log(name, 'join', JSON.stringify(await p.rpc('join', { name, host: false })));
  return p;
}

(async () => {
  setTimeout(() => { console.error('timed out'); process.exit(1); }, 150000);
  const ann = await phone('Ann');
  const bob = await phone('Bob');
  const cat = await phone('Cat');
  await wait(1500);
  shot('1-lobby');
  console.log('start', JSON.stringify(await ann.act({ type: 'start' })));
  await wait(1500);
  shot('2-board');
  const ctrl = [ann, bob, cat].find((p) => p.pid === ann.state.controllerId);
  const board = ann.state.board;
  // Pick a clue that is not a daily double if we can tell; the TV hides that, so just pick the top-left.
  console.log('pick', JSON.stringify(await ctrl.act({ type: 'pick', ci: 0, ri: 0 })));
  await wait(800);
  shot('3-clue');
  if (ann.state.phase === 'dd-wager') {
    console.log('daily double', JSON.stringify(await ctrl.act({ type: 'ddWager', amount: 500 })));
  } else {
    for (let i = 0; i < 20 && ann.state.phase !== 'open'; i++) await wait(500);
    shot('4-open');
    console.log('buzz', JSON.stringify(await bob.act({ type: 'buzz' })));
    await wait(800);
    shot('5-answering');
    console.log('answer', JSON.stringify(await bob.act({ type: 'answer', text: 'something wrong' })));
    await wait(800);
    console.log('buzz2', JSON.stringify(await cat.act({ type: 'buzz' })));
    await wait(300);
    console.log('answer2', JSON.stringify(await cat.act({ type: 'answer', text: 'four' })));
  }
  // Ann buzzes and the captain flips her answer to correct, so she has money for the final.
  for (let i = 0; i < 10 && ann.state.phase !== 'open'; i++) await wait(300);
  console.log('ann buzz', JSON.stringify(await ann.act({ type: 'buzz' })));
  await wait(300);
  console.log('ann answer', JSON.stringify(await ann.act({ type: 'answer', text: 'no idea' })));
  await wait(500);
  console.log('flip', JSON.stringify(await ann.act({ type: 'override' })));
  await wait(1200);
  shot('6-reveal');
  const until = async (ph) => { for (let i = 0; i < 30 && ann.state.phase !== ph; i++) await wait(300); };
  await ann.act({ type: 'advance' });
  await until('board');
  console.log('end round', JSON.stringify(await ann.act({ type: 'endRound' })));
  await until('round-end');
  await wait(800);
  shot('7-round-end');
  await ann.act({ type: 'advance' });
  await until('board');
  await wait(1000);
  shot('7b-round2-board');
  await ann.act({ type: 'endRound' });
  await until('round-end');
  await ann.act({ type: 'advance' });
  await wait(1500);
  shot('8-final-or-gameover');
  const st = ann.state;
  if (st.phase === 'final-wager') {
    for (const p of [ann, bob, cat]) if (st.final.eligible.includes(p.pid)) await p.act({ type: 'finalWager', amount: 100 });
    await wait(1500);
    shot('9-final-answer');
    for (const p of [ann, bob, cat]) if (st.final.eligible.includes(p.pid)) await p.act({ type: 'finalAnswer', text: 'a guess' });
    await wait(3500);
    shot('10-final-reveal');
    for (let i = 0; i < 6 && ann.state.phase !== 'gameover'; i++) { await ann.act({ type: 'advance' }); await wait(700); }
    await wait(1000);
  }
  shot('11-gameover');
  process.exit(0);
})();
