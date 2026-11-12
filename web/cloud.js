// Online mode: no game server. The TV page runs the game itself, and phones
// talk to it through Supabase Realtime broadcast channels.
//   bw:ROOM        phones -> TV (join, act, hello, heartbeat)
//   bw:ROOM:PID    TV -> one phone (its own game state and replies)
const Cloud = (() => {
  const cfg = window.BW_CONFIG || {};
  let client = null;
  const sb = () => client || (client = supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey, {
    realtime: { params: { eventsPerSecond: 40 } },
    auth: { persistSession: false, autoRefreshToken: false },
  }));
  const hex = (n) => [...crypto.getRandomValues(new Uint8Array(n))].map((b) => b.toString(16).padStart(2, '0')).join('');

  function open(name, events) {
    const ch = sb().channel(name, { config: { broadcast: { self: false, ack: false } } });
    for (const [e, fn] of Object.entries(events)) ch.on('broadcast', { event: e }, (m) => fn(m.payload || {}));
    let ready;
    const p = new Promise((r) => (ready = r));
    ch.subscribe((status) => { if (status === 'SUBSCRIBED') ready(); });
    return {
      ch,
      ready: p,
      send: async (event, payload) => { await p; return ch.send({ type: 'broadcast', event, payload }); },
      close: () => sb().removeChannel(ch),
    };
  }

  // ---------- TV side ----------
  let tvCb = null, lastTvState = null, hubApi = null;

  async function loadPacks() {
    const ids = await fetch('/questions/index.json').then((r) => r.json());
    const packs = await Promise.all(ids.map((id) => fetch(`/questions/${id}.json`).then((r) => r.json())
      .then((d) => BWRules.normalizePack(id, d)).catch(() => null)));
    const out = packs.filter((p) => p && p.categories.length);
    // Real show boards from the clue archive. When they load, they are the
    // default and the house packs start switched off (tap to add them back).
    try {
      if (!window.BWArchive) await new Promise((ok, fail) => {
        const el = document.createElement('script');
        el.src = '/archive.js';
        el.onload = ok;
        el.onerror = fail;
        document.head.appendChild(el);
      });
      if (window.BWArchive) {
        const arc = (await BWArchive.load()).map((p) => BWRules.normalizePack(p.id, p)).filter((p) => p.categories.length);
        if (arc.length) {
          for (const p of out) p.selected = false;
          out.unshift(...arc);
        }
      }
    } catch (e) { console.warn('Archive pack unavailable', e); }
    return out;
  }

  async function hubCreate() {
    const packs = await loadPacks();
    const letters = 'BCDFGHJKLMNPQRSTVWXZ';
    const code = Array.from({ length: 4 }, () => letters[Math.floor(Math.random() * letters.length)]).join('');
    const chans = new Map();
    const lastSeen = new Map();
    const online = new Set();
    let pending = null;

    const game = new BWGame.Game(code, packs, () => { if (!pending) pending = setTimeout(flush, 25); });
    const known = (pid) => game.players.has(pid) || (pid && pid === game.hostId);
    const chFor = (pid) => { if (!chans.has(pid)) chans.set(pid, open(`bw:${code}:${pid}`, {})); return chans.get(pid); };
    const sendState = (pid) => known(pid) && chFor(pid).send('state', game.view(pid === game.hostId ? 'host' : 'player', pid));
    const reply = (pid, reqId, result) => chFor(pid).send('reply', { reqId, result });

    function flush() {
      pending = null;
      lastTvState = game.view('tv');
      tvCb && tvCb(lastTvState);
      for (const pid of online) sendState(pid);
    }
    function seen(pid) {
      lastSeen.set(pid, Date.now());
      if (!online.has(pid) && known(pid)) { online.add(pid); game.setConnected(pid, +1); }
    }
    // A phone that stops checking in for 12 seconds counts as disconnected.
    setInterval(() => {
      const now = Date.now();
      for (const pid of [...online]) {
        if (!known(pid)) { online.delete(pid); continue; }
        if (now - (lastSeen.get(pid) || 0) > 12000) { online.delete(pid); game.setConnected(pid, -1); }
      }
    }, 3000);

    const valid = (pid) => typeof pid === 'string' && /^[a-f0-9]{16}$/.test(pid);
    const main = open(`bw:${code}`, {
      join: ({ pid, name, host, reqId }) => {
        if (!valid(pid)) return;
        const r = host ? game.joinHost(pid, name) : game.join(pid, name);
        if (r.error) return reply(pid, reqId, r);
        reply(pid, reqId, { pid, code });
        seen(pid);
        sendState(pid);
      },
      hello: ({ pid }) => {
        if (!valid(pid)) return;
        if (known(pid)) { seen(pid); sendState(pid); } else chFor(pid).send('state', { gone: true });
      },
      hb: ({ pid }) => { if (valid(pid) && known(pid)) seen(pid); },
      act: ({ pid, reqId, body }) => {
        if (!valid(pid)) return;
        seen(pid);
        const r = BWRules.act(game, 'player', pid, { ...(body || {}), pid }) || { ok: true };
        reply(pid, reqId, r);
      },
    });
    await main.ready;
    hubApi = { game, act: (body) => BWRules.act(game, 'tv', null, body) || { ok: true } };
    // Closing or reloading the TV page ends the game, so warn first.
    window.addEventListener('beforeunload', (e) => {
      if (game.phase !== 'lobby' && game.phase !== 'gameover') { e.preventDefault(); e.returnValue = ''; }
    });
    flush();
    return { code, tvKey: 'local' };
  }

  function tvSubscribe(cb) {
    tvCb = (s) => cb({ ...s, _skew: 0 });
    if (lastTvState) tvCb(lastTvState);
  }

  // ---------- phone side ----------
  const phone = { room: null, pid: null, ch: null, main: null, pending: new Map(), onState: null, hb: null };

  function phoneSetup(room, pid) {
    if (phone.room === room && phone.pid === pid) return;
    if (phone.ch) { phone.ch.close(); phone.main.close(); clearInterval(phone.hb); }
    phone.room = room;
    phone.pid = pid;
    phone.ch = open(`bw:${room}:${pid}`, {
      state: (s) => phone.onState && phone.onState(s),
      reply: ({ reqId, result }) => {
        const f = phone.pending.get(reqId);
        if (f) { phone.pending.delete(reqId); f(result); }
      },
    });
    phone.main = open(`bw:${room}`, {});
    phone.hb = setInterval(() => phone.main.send('hb', { pid }), 4000);
  }

  function rpc(event, payload, failMsg) {
    const reqId = hex(6);
    return new Promise(async (resolve) => {
      const t = setTimeout(() => { phone.pending.delete(reqId); resolve({ error: failMsg }); }, 6000);
      phone.pending.set(reqId, (r) => { clearTimeout(t); resolve(r || { ok: true }); });
      await phone.ch.ready;
      await phone.main.send(event, { ...payload, reqId });
    });
  }

  function join(body) {
    const room = String(body.room || '').toUpperCase();
    const pid = typeof body.pid === 'string' && /^[a-f0-9]{16}$/.test(body.pid) ? body.pid : hex(8);
    phoneSetup(room, pid);
    return rpc('join', { pid, name: body.name, host: !!body.host }, 'Room not found. Check the code on the TV.');
  }

  function act(body) {
    const { room, pid, ...rest } = body;
    phoneSetup(String(room).toUpperCase(), pid);
    return rpc('act', { pid, body: rest }, 'Lost connection to the TV. Try again.');
  }

  function phoneSubscribe(params, cb, onStatus) {
    phoneSetup(String(params.room).toUpperCase(), params.pid);
    phone.onState = (s) => {
      if (s.gone) return cb({ me: null, gone: true });
      s._skew = Date.now() - s.now;
      onStatus && onStatus(true);
      cb(s);
    };
    const hello = () => phone.main.send('hello', { pid: phone.pid });
    phone.ch.ready.then(hello);
    // Phones sleep a lot; ask for fresh state when the page comes back.
    document.addEventListener('visibilitychange', () => { if (!document.hidden) hello(); });
    return () => {};
  }

  return { hubCreate, tvSubscribe, join, act, phoneSubscribe, tvAct: (body) => Promise.resolve(hubApi ? hubApi.act(body) : { error: 'not ready' }) };
})();
