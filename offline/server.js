// Buzzworthy server: no dependencies, just run `node server.js`.
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { Game } = require('./public/engine/game');
const { normalizePack, act } = require('./public/engine/rules');

const PORT = Number(process.env.PORT) || 3000;
const PUBLIC = path.join(__dirname, 'public');
const QDIR = path.join(__dirname, 'public', 'questions');

// ---------- question packs ----------
// Each .json file in the questions folder is one pack. Players choose packs in the lobby.
function loadPacks() {
  const packs = [];
  const files = fs.readdirSync(QDIR).filter((x) => x.endsWith('.json') && x !== 'index.json').sort();
  for (const f of files) {
    try {
      const pack = normalizePack(f.replace(/\.json$/, ''), JSON.parse(fs.readFileSync(path.join(QDIR, f), 'utf8')));
      if (pack.categories.length) packs.push(pack);
    } catch (e) {
      console.error(`Skipping questions/${f}: ${e.message}`);
    }
  }
  if (!packs.length) {
    console.error('No question packs found in the questions folder.');
    process.exit(1);
  }
  // Keep the pack list current for the online version of the TV page.
  try { fs.writeFileSync(path.join(QDIR, 'index.json'), JSON.stringify(packs.map((p) => p.id))); } catch (e) {}
  return packs;
}
const packs = loadPacks();

// ---------- rooms ----------
const rooms = new Map(); // code -> { game, clients:Set }

function newCode() {
  const letters = 'BCDFGHJKLMNPQRSTVWXZ';
  let code;
  do {
    code = Array.from({ length: 4 }, () => letters[Math.floor(Math.random() * letters.length)]).join('');
  } while (rooms.has(code));
  return code;
}

function createRoom() {
  const code = newCode();
  const room = { clients: new Set() };
  room.game = new Game(code, packs, () => broadcast(room));
  rooms.set(code, room);
  return room;
}

function broadcast(room) {
  for (const c of room.clients) send(c, room.game.view(c.role, c.pid));
}

function send(client, data) {
  client.res.write(`data: ${JSON.stringify(data)}\n\n`);
}

// Clean up rooms idle for 6 hours.
setInterval(() => {
  const cutoff = Date.now() - 6 * 3600 * 1000;
  for (const [code, room] of rooms) {
    if (room.clients.size === 0 && room.game.lastActive < cutoff) rooms.delete(code);
  }
}, 10 * 60 * 1000);

// ---------- helpers ----------
function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list || []) if (a.family === 'IPv4' && !a.internal) out.push(a.address);
  }
  // Prefer typical home network ranges.
  out.sort((a, b) => score(b) - score(a));
  function score(ip) {
    if (ip.startsWith('192.168.')) return 3;
    if (ip.startsWith('10.')) return 2;
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(ip)) return 1;
    return 0;
  }
  return out;
}

function json(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (c) => { data += c; if (data.length > 1e5) req.destroy(); });
    req.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch { resolve({}); } });
  });
}

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon' };

function serveFile(res, file) {
  const full = path.join(PUBLIC, file);
  if (!full.startsWith(PUBLIC)) return json(res, 404, { error: 'not found' });
  fs.readFile(full, (err, buf) => {
    if (err) return json(res, 404, { error: 'not found' });
    res.writeHead(200, { 'Content-Type': MIME[path.extname(full)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(buf);
  });
}

// ---------- actions ----------

// ---------- http ----------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = url.pathname;

  if (req.method === 'GET' && (p === '/' || p === '/tv')) return serveFile(res, 'tv.html');
  if (req.method === 'GET' && (p === '/play' || p === '/join')) return serveFile(res, 'play.html');

  if (req.method === 'GET' && p === '/config.js') {
    res.writeHead(200, { 'Content-Type': 'text/javascript', 'Cache-Control': 'no-cache' });
    return res.end("window.BW_CONFIG = { mode: 'local' };");
  }

  if (req.method === 'GET' && p === '/api/info') {
    return json(res, 200, { port: PORT, addresses: lanAddresses() });
  }

  if (req.method === 'POST' && p === '/api/create') {
    const room = createRoom();
    return json(res, 200, { code: room.game.code, tvKey: room.tvKey = crypto.randomBytes(8).toString('hex') });
  }

  if (req.method === 'POST' && p === '/api/join') {
    const body = await readBody(req);
    const room = rooms.get(String(body.room || '').toUpperCase());
    if (!room) return json(res, 404, { error: 'Room not found. Check the code on the TV.' });
    const pid = typeof body.pid === 'string' && /^[a-f0-9]{16}$/.test(body.pid) ? body.pid : crypto.randomBytes(8).toString('hex');
    const r = body.host ? room.game.joinHost(pid, body.name) : room.game.join(pid, body.name);
    if (r.error) return json(res, 400, r);
    return json(res, 200, { pid, code: room.game.code });
  }

  if (req.method === 'POST' && p === '/api/act') {
    const body = await readBody(req);
    const room = rooms.get(String(body.room || '').toUpperCase());
    if (!room) return json(res, 404, { error: 'Room not found' });
    const role = body.tvKey && body.tvKey === room.tvKey ? 'tv' : 'player';
    return json(res, 200, act(room.game, role, body.pid, body) || { ok: true });
  }

  if (req.method === 'GET' && p === '/events') {
    const room = rooms.get(String(url.searchParams.get('room') || '').toUpperCase());
    if (!room) return json(res, 404, { error: 'Room not found' });
    const tvKey = url.searchParams.get('tvKey');
    const pid = url.searchParams.get('pid') || null;
    let role = tvKey && tvKey === room.tvKey ? 'tv' : 'player';
    if (role === 'player' && pid && pid === room.game.hostId) role = 'host';
    if (role === 'player' && !room.game.players.has(pid)) return json(res, 404, { error: 'Join first' });
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    res.write('retry: 1500\n\n');
    const client = { res, role, pid };
    room.clients.add(client);
    if (role !== 'tv') room.game.setConnected(pid, +1);
    send(client, room.game.view(role, pid));
    const ping = setInterval(() => res.write(': ping\n\n'), 15000);
    req.on('close', () => {
      clearInterval(ping);
      room.clients.delete(client);
      if (role !== 'tv') room.game.setConnected(pid, -1);
    });
    return;
  }

  if (req.method === 'GET') return serveFile(res, p.slice(1));
  json(res, 404, { error: 'not found' });
});

server.listen(PORT, '0.0.0.0', () => {
  const ips = lanAddresses();
  console.log('\n  BUZZWORTHY is running!\n');
  console.log(`  TV screen:   http://${ips[0] || 'localhost'}:${PORT}`);
  if (ips.length > 1) console.log(`  (other addresses: ${ips.slice(1).map((ip) => `http://${ip}:${PORT}`).join(', ')})`);
  for (const pk of packs) console.log(`  Pack "${pk.title}": ${pk.categories.length} categories, ${pk.finals.length} finals${pk.selected ? '' : ' (off by default)'}`);
  console.log('\n  Open the TV link on your TV or laptop, then players scan the QR code.\n');
});
