// Apple TV glue. The game engine (judge.js, game.js, rules.js) is the exact
// same code the web TV page runs. This file plays the part of cloud.js:
// it runs the room and talks to phones through the native Supabase link.
//   bw:ROOM        phones -> TV (join, act, hello, hb)
//   bw:ROOM:PID    TV -> one phone (its own game state and replies)
var Hub = (function () {
  var game = null;
  var code = '';
  var online = new Set();
  var lastSeen = new Map();
  var pending = null;
  var sweeper = null;

  function known(pid) {
    return !!game && (game.players.has(pid) || (!!pid && pid === game.hostId));
  }
  function send(pid, event, payload) {
    __native.send('bw:' + code + ':' + pid, event, JSON.stringify(payload));
  }
  function sendState(pid) {
    if (known(pid)) send(pid, 'state', game.view(pid === game.hostId ? 'host' : 'player', pid));
  }
  function reply(pid, reqId, result) {
    send(pid, 'reply', { reqId: reqId, result: result });
  }
  function flush() {
    pending = null;
    if (!game) return;
    __native.state(JSON.stringify(game.view('tv')));
    online.forEach(sendState);
  }
  function seen(pid) {
    lastSeen.set(pid, Date.now());
    if (!online.has(pid) && known(pid)) {
      online.add(pid);
      game.setConnected(pid, +1);
    }
  }
  // A phone that stops checking in for 12 seconds counts as disconnected.
  function sweep() {
    if (!game) return;
    var now = Date.now();
    Array.from(online).forEach(function (pid) {
      if (!known(pid)) { online.delete(pid); return; }
      if (now - (lastSeen.get(pid) || 0) > 12000) {
        online.delete(pid);
        game.setConnected(pid, -1);
      }
    });
  }
  function valid(pid) {
    return typeof pid === 'string' && /^[a-f0-9]{16}$/.test(pid);
  }
  function makeCode() {
    var letters = 'BCDFGHJKLMNPQRSTVWXZ';
    var out = '';
    for (var i = 0; i < 4; i++) out += letters[Math.floor(Math.random() * letters.length)];
    return out;
  }

  function create(packsJSON) {
    var raw = JSON.parse(packsJSON);
    var packs = raw
      .map(function (p) { return BWRules.normalizePack(p.id, p.data); })
      .filter(function (p) { return p && p.categories.length; });
    if (game) game.clearTimer();
    if (pending) clearTimeout(pending);
    pending = null;
    code = makeCode();
    online = new Set();
    lastSeen = new Map();
    var g = new BWGame.Game(code, packs, function () {
      if (g === game && !pending) pending = setTimeout(flush, 25);
    });
    game = g;
    if (!sweeper) sweeper = setInterval(sweep, 3000);
    flush();
    return code;
  }

  function onMessage(event, json) {
    if (!game) return;
    var m = {};
    try { m = JSON.parse(json || '{}') || {}; } catch (e) { return; }
    var pid = m.pid;
    if (!valid(pid)) return;
    if (event === 'join') {
      var r = m.host ? game.joinHost(pid, m.name) : game.join(pid, m.name);
      if (r && r.error) return reply(pid, m.reqId, r);
      reply(pid, m.reqId, { pid: pid, code: code });
      seen(pid);
      sendState(pid);
    } else if (event === 'hello') {
      if (known(pid)) { seen(pid); sendState(pid); } else send(pid, 'state', { gone: true });
    } else if (event === 'hb') {
      if (known(pid)) seen(pid);
    } else if (event === 'act') {
      seen(pid);
      var body = Object.assign({}, m.body || {}, { pid: pid });
      var res = BWRules.act(game, 'player', pid, body) || { ok: true };
      reply(pid, m.reqId, res);
    }
  }

  function act(json) {
    if (!game) return JSON.stringify({ error: 'not ready' });
    var body = {};
    try { body = JSON.parse(json || '{}') || {}; } catch (e) {}
    return JSON.stringify(BWRules.act(game, 'tv', null, body) || { ok: true });
  }

  // After the network comes back, push fresh state to every phone.
  function resendAll() {
    online.forEach(sendState);
  }

  return { create: create, onMessage: onMessage, act: act, resendAll: resendAll };
})();
