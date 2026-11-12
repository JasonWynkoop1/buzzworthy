// Shared helpers for the TV and phone pages.
const BW = {
  esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
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
        el.textContent = left == null ? '' : Math.ceil(left / 1000);
      });
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  },
};

// Little synth so we don't ship any audio files.
const Sound = {
  ctx: null,
  on: false,
  enable() {
    try {
      this.ctx = this.ctx || new (window.AudioContext || window.webkitAudioContext)();
      this.ctx.resume();
      this.on = true;
    } catch (e) {}
  },
  tone(freq, dur, type = 'sine', vol = 0.2, when = 0, slideTo) {
    if (!this.on || !this.ctx) return;
    const t = this.ctx.currentTime + when;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, t + dur);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(this.ctx.destination);
    o.start(t);
    o.stop(t + dur + 0.05);
  },
  pick() { this.tone(660, 0.12, 'triangle'); this.tone(990, 0.15, 'triangle', 0.15, 0.08); },
  open() { this.tone(880, 0.08, 'square', 0.08); },
  buzz() { this.tone(220, 0.35, 'sawtooth', 0.18, 0, 440); },
  correct() { [523, 659, 784, 1047].forEach((f, i) => this.tone(f, 0.25, 'triangle', 0.18, i * 0.09)); },
  wrong() { this.tone(180, 0.5, 'square', 0.12, 0, 90); },
  timeout() { this.tone(300, 0.25, 'sine', 0.15); this.tone(240, 0.4, 'sine', 0.15, 0.25); },
  dd() { [392, 523, 659, 784, 1047, 1319].forEach((f, i) => this.tone(f, 0.3, 'sawtooth', 0.08, i * 0.07)); },
  fanfare() { [523, 523, 523, 659, 784, 659, 784, 1047].forEach((f, i) => this.tone(f, 0.3, 'triangle', 0.18, i * 0.14)); },
  tick() { this.tone(1200, 0.04, 'square', 0.04); },
};
