// Shared helpers for the TV and phone pages.
const BW = {
  esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  },
  // Labels for the archive era buttons.
  ERA_LABELS: { any: 'Any era', classic: 'Classic 80s & 90s', '2000s': '2000s', recent: 'Recent' },
  // "Season 12 (1995-96)". Season N first aired in the fall of 1983 + N.
  seasonLabel(n) {
    if (!n) return '';
    const y = 1983 + n;
    return `Season ${n} (${y}-${String((y + 1) % 100).padStart(2, '0')})`;
  },
  money(n) {
    const s = '$' + Math.abs(n).toLocaleString();
    return n < 0 ? '-' + s : s;
  },
  cloud: !!(window.BW_CONFIG && window.BW_CONFIG.mode === 'cloud'),
  async post(url, body) {
    if (BW.cloud) {
      if (url === '/api/create') return Cloud.hubCreate();
      if (url === '/api/join') return Cloud.join(body);
      if (url === '/api/act') return body.tvKey ? Cloud.tvAct(body) : Cloud.act(body);
      return { error: 'unsupported' };
    }
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      return await r.json();
    } catch (e) {
      return { error: 'Network error' };
    }
  },
  // Keeps a live connection and calls onState with each update.
  connect(params, onState, onStatus) {
    if (BW.cloud) {
      if (params.tvKey) { onStatus && onStatus(true); return Cloud.tvSubscribe(onState); }
      return Cloud.phoneSubscribe(params, onState, onStatus);
    }
    let es;
    const open = () => {
      es = new EventSource('/events?' + new URLSearchParams(params));
      es.onopen = () => onStatus && onStatus(true);
      es.onmessage = (e) => {
        const s = JSON.parse(e.data);
        s._skew = Date.now() - s.now;
        onState(s);
      };
      es.onerror = () => {
        onStatus && onStatus(false);
        if (es.readyState === EventSource.CLOSED) setTimeout(open, 2000);
      };
    };
    open();
    return () => es && es.close();
  },
  remaining(s) {
    if (!s || !s.deadline) return null;
    return Math.max(0, s.deadline + s._skew - Date.now());
  },
  // Drives elements with [data-timer] to show the time left in the current state.
  startTimerLoop(getState) {
    const tick = () => {
      const s = getState();
      document.querySelectorAll('[data-timer-bar]').forEach((el) => {
        const total = Number(el.dataset.total) || 1;
        const left = BW.remaining(s);
        el.style.transform = `scaleX(${left == null ? 0 : Math.min(1, left / total)})`;
      });
      document.querySelectorAll('[data-timer-text]').forEach((el) => {
        const left = BW.remaining(s);
        const t = left == null ? '' : left <= 0 && el.dataset.zero ? el.dataset.zero : Math.ceil(left / 1000);
        if (el.textContent !== String(t)) el.textContent = t;
      });
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  },
};

// Recorded sounds and music (all CC0, see sounds/CREDITS.txt), the same ones the Apple TV app plays.
// Browsers only allow audio after a click or key press on the page, so the TV
// page calls Sound.unlock() on the first one. Sound effects and the music each
// have their own on/off switch, remembered on this computer.
const Sound = {
  NAMES: ['pick', 'open', 'buzz', 'correct', 'wrong', 'timeout', 'dd', 'board', 'think', 'fanfare', 'theme'],
  els: {},
  unlocked: false,
  fx: true,
  musicOn: true,
  want: null,        // the music that should be playing now ('theme', 'think' or null)
  fade: null,
  init() {
    try { this.fx = localStorage.getItem('bw-fx') !== '0'; this.musicOn = localStorage.getItem('bw-music') !== '0'; } catch (e) {}
    for (const n of this.NAMES) {
      const a = new Audio('/sounds/' + n + '.mp3');
      a.preload = 'auto';
      if (n === 'theme') { a.loop = true; a.volume = 0.45; }
      this.els[n] = a;
    }
  },
  // Try to start audio. Resolves true when the browser allowed it.
  unlock() {
    if (this.unlocked) return Promise.resolve(true);
    const a = this.els.open;
    a.volume = 0;
    return a.play().then(() => {
      a.pause(); a.currentTime = 0; a.volume = 1;
      this.unlocked = true;
      this.sync();
      return true;
    }).catch(() => { a.volume = 1; return false; });
  },
  play(n) {
    const a = this.els[n];
    if (!a || !this.fx || !this.unlocked) return;
    try { a.currentTime = 0; } catch (e) {}
    a.play().catch(() => {});
  },
  // Music: the lobby theme or the final-round thinking music.
  music(n) {
    if (this.want === n) return;
    this.want = n;
    this.sync();
  },
  sync() {
    if (!this.unlocked) return;
    for (const n of ['theme', 'think']) {
      const a = this.els[n];
      const on = this.want === n && (n === 'think' ? this.fx : this.musicOn);
      if (on && a.paused) {
        if (n === 'theme') { a.volume = 0; this.fadeTo(a, 0.45); }
        else { try { a.currentTime = 0; } catch (e) {} a.volume = 0.8; }
        a.play().catch(() => {});
      } else if (!on && !a.paused) {
        if (n === 'theme') this.fadeTo(a, 0, () => a.pause());
        else a.pause();
      }
    }
  },
  fadeTo(a, target, done) {
    clearInterval(this.fade);
    const step = (target - a.volume) / 12;
    let i = 0;
    this.fade = setInterval(() => {
      i++;
      a.volume = Math.max(0, Math.min(1, i >= 12 ? target : a.volume + step));
      if (i >= 12) { clearInterval(this.fade); done && done(); }
    }, 40);
  },
  setFx(on) { this.fx = on; try { localStorage.setItem('bw-fx', on ? '1' : '0'); } catch (e) {} this.sync(); },
  setMusic(on) { this.musicOn = on; try { localStorage.setItem('bw-music', on ? '1' : '0'); } catch (e) {} this.sync(); },
};
