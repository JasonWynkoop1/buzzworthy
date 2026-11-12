(function () {
// Core game logic for Buzzworthy. One Game instance per room.
// Runs on the Node server (local mode) or inside the TV's browser (online mode).
const { judge } = typeof module !== 'undefined' && module.exports ? require('./judge') : window.BWJudge;

const COLORS = ['#ff5d8f', '#4cc9f0', '#ffd166', '#06d6a0', '#c77dff', '#ff9f1c', '#90e0ef', '#f15bb5'];
const MAX_PLAYERS = 8;
const SPEED = (typeof process !== 'undefined' && Number(process.env.BW_SPEED)) || 1; // test hook: speeds up all timers

const T = {
  buzzWindow: 7000,     // time to buzz after the clue unlocks
  rebuzzWindow: 6000,   // time to buzz after someone misses
  answer: 15000,        // time to type an answer after buzzing
  ddAnswer: 20000,      // daily double answer time (after reading)
  reveal: 4500,         // how long the correct answer stays up
  earlyPenalty: 400,    // lockout for buzzing before the clue unlocks
  finalAnswer: 35000,
  finalStep: 6500,
  hostRead: 30000,      // host mode: fallback if the host forgets to open buzzers
  hostAnswer: 30000,    // host mode: time for the host to judge a spoken answer
};

function readingTime(text) {
  return Math.max(2500, Math.min(7000, 1200 + text.length * 45));
}

function shuffle(a) {
  a = a.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

class Game {
  constructor(code, packs, onChange) {
    this.code = code;
    this.packs = packs;
    this.selectedPacks = new Set(packs.filter((pk) => pk.selected).map((pk) => pk.id));
    if (!this.selectedPacks.size) this.selectedPacks.add(packs[0].id);
    this.onChange = onChange;
    this.players = new Map();
    this.order = [];
    this.captainId = null;
    this.hostId = null;       // optional host: reads clues and judges spoken answers
    this.hostName = '';
    this.hostConnections = 0;
    this.phase = 'lobby';
    this.round = 0;
    this.rounds = [];
    this.controllerId = null;
    this.clue = null;
    this.timer = null;
    this.deadline = null;
    this.lastResult = null;
    this.final = null;
    this.lastActive = Date.now();
    this.events = 0;
  }

  // ---------- setup ----------
  // Categories and finals from the chosen packs, without duplicate category names.
  bank() {
    const chosen = this.packs.filter((pk) => this.selectedPacks.has(pk.id));
    const seen = new Set();
    const categories = [];
    for (const pk of chosen) for (const c of pk.categories) {
      const k = c.name.toLowerCase();
      if (!seen.has(k)) { seen.add(k); categories.push(c); }
    }
    let finals = chosen.flatMap((pk) => pk.finals);
    if (!finals.length) finals = this.packs.flatMap((pk) => pk.finals);
    return { categories, finals };
  }

  togglePack(id) {
    if (this.phase !== 'lobby' || !this.packs.some((pk) => pk.id === id)) return;
    if (this.selectedPacks.has(id)) this.selectedPacks.delete(id);
    else this.selectedPacks.add(id);
    this.touch();
  }

  buildRounds() {
    const bank = this.bank();
    const cats = shuffle(bank.categories);
    const used = new Set();
    const pick = () => {
      const out = [];
      for (const c of cats) {
        if (out.length === 6) break;
        if (used.has(c.name) || c.clues.length < 5) continue;
        used.add(c.name);
        out.push(c);
      }
      return out;
    };
    const mk = (r, cs, ddCount) => {
      const board = cs.map((c) => ({
        name: c.name,
        clues: c.clues.slice(0, 5).map((cl, i) => ({
          value: (i + 1) * 200 * r,
          q: cl.q,
          a: cl.a,
          alt: cl.alt || [],
          used: false,
          dd: false,
        })),
      }));
      // Daily doubles prefer the harder rows.
      const slots = [];
      board.forEach((c, ci) => c.clues.forEach((cl, ri) => {
        const w = [0, 1, 3, 4, 3][ri];
        for (let k = 0; k < w; k++) slots.push([ci, ri]);
      }));
      const usedCols = new Set();
      let tries = 0;
      while (ddCount > 0 && tries++ < 200) {
        const [ci, ri] = slots[Math.floor(Math.random() * slots.length)];
        if (usedCols.has(ci)) continue;
        usedCols.add(ci);
        board[ci].clues[ri].dd = true;
        ddCount--;
      }
      return board;
    };
    this.rounds = [mk(1, pick(), 1), mk(2, pick(), 2)];
    const f = shuffle(bank.finals)[0];
    this.finalClue = f ? { category: f.category, q: f.q, a: f.a, alt: f.alt || [] } : null;
  }

  // ---------- players ----------
  join(pid, name) {
    name = String(name || '').trim().slice(0, 16) || 'Player';
    let p = this.players.get(pid);
    if (p) {
      p.name = name;
    } else {
      if (this.players.size >= MAX_PLAYERS) return { error: 'Room is full (8 players max).' };
      const usedColors = new Set([...this.players.values()].map((x) => x.color));
      p = {
        id: pid,
        name,
        score: 0,
        color: COLORS.find((c) => !usedColors.has(c)) || COLORS[0],
        connections: 0,
        lockUntil: 0,
      };
      this.players.set(pid, p);
      this.order.push(pid);
      if (!this.captainId) this.captainId = pid;
    }
    this.touch();
    return { ok: true };
  }

  get hostMode() {
    return !!this.hostId;
  }

  // Who gets the captain controls: the host if there is one.
  captain() {
    return this.hostId || this.captainId;
  }

  joinHost(pid, name) {
    if (this.hostId && this.hostId !== pid) return { error: 'This room already has a host.' };
    if (this.players.has(pid)) {
      if (this.phase !== 'lobby') return { error: 'You are already playing in this game.' };
      this.kick(pid);
    }
    this.hostId = pid;
    this.hostName = String(name || '').trim().slice(0, 16) || 'Host';
    this.touch();
    return { ok: true };
  }

  leaveHost(pid) {
    if (this.hostId !== pid) return;
    this.hostId = null;
    this.hostName = '';
    this.hostConnections = 0;
    this.touch();
  }

  kick(pid) {
    if (!this.players.has(pid)) return;
    this.players.delete(pid);
    this.order = this.order.filter((x) => x !== pid);
    if (this.captainId === pid) this.captainId = this.order[0] || null;
    if (this.controllerId === pid) this.controllerId = this.order[0] || null;
    this.touch();
  }

  setConnected(pid, delta) {
    if (pid && pid === this.hostId) {
      this.hostConnections = Math.max(0, this.hostConnections + delta);
      this.touch();
      return;
    }
    const p = this.players.get(pid);
    if (!p) return;
    p.connections = Math.max(0, p.connections + delta);
    // Hand the captain role to someone online if the captain drops for good.
    if (this.captainId === pid && p.connections === 0) {
      setTimeout(() => {
        const cap = this.players.get(this.captainId);
        if (cap && cap.connections === 0) {
          const next = this.order.find((id) => this.players.get(id).connections > 0);
          if (next) { this.captainId = next; this.touch(); }
        }
      }, 15000);
    }
    this.touch();
  }

  isConnected(pid) {
    const p = this.players.get(pid);
    return !!p && p.connections > 0;
  }

  // ---------- flow ----------
  setTimer(ms, fn) {
    ms = ms / SPEED;
    clearTimeout(this.timer);
    this.deadline = Date.now() + ms;
    this.duration = ms;
    this.timer = setTimeout(() => { this.timer = null; fn(); }, ms);
  }

  clearTimer() {
    clearTimeout(this.timer);
    this.timer = null;
    this.deadline = null;
  }

  touch() {
    this.lastActive = Date.now();
    this.events++;
    this.onChange && this.onChange();
  }

  board() {
    return this.round >= 1 && this.round <= 2 ? this.rounds[this.round - 1] : null;
  }

  start() {
    if (this.phase !== 'lobby' || this.players.size === 0) return;
    if (this.bank().categories.length < 12) return { error: 'Pick packs with at least 12 categories in total.' };
    this.buildRounds();
    this.round = 1;
    this.controllerId = this.order[Math.floor(Math.random() * this.order.length)];
    this.phase = 'board';
    this.touch();
  }

  pick(ci, ri) {
    if (this.phase !== 'board') return;
    const b = this.board();
    const cl = b && b[ci] && b[ci].clues[ri];
    if (!cl || cl.used) return;
    cl.used = true;
    this.lastResult = null;
    this.clue = { ci, ri, cat: b[ci].name, value: cl.value, q: cl.q, a: cl.a, alt: cl.alt, dd: cl.dd, tried: [], buzzedId: null, wager: null };
    if (cl.dd) {
      this.phase = 'dd-wager';
      this.clearTimer();
    } else {
      this.phase = 'reading';
      // With a host, buzzers open when the host finishes reading aloud.
      this.setTimer(this.hostMode ? T.hostRead : readingTime(cl.q), () => this.openBuzzers(T.buzzWindow));
    }
    this.touch();
  }

  openNow() {
    if (this.phase === 'reading') this.openBuzzers(T.buzzWindow);
  }

  openBuzzers(window) {
    this.phase = 'open';
    this.clue.buzzedId = null;
    this.setTimer(window, () => this.endClue());
    this.touch();
  }

  buzz(pid) {
    const p = this.players.get(pid);
    if (!p || !this.clue) return { result: 'ignored' };
    const now = Date.now();
    if (this.phase === 'reading') {
      p.lockUntil = now + T.earlyPenalty;
      return { result: 'early' };
    }
    if (this.phase !== 'open') return { result: 'ignored' };
    if (this.clue.tried.includes(pid)) return { result: 'tried' };
    if (now < p.lockUntil) return { result: 'early' };
    this.clue.buzzedId = pid;
    this.phase = 'answering';
    this.setTimer(this.hostMode ? T.hostAnswer : T.answer, () => this.submitAnswer(pid, '', true));
    this.touch();
    return { result: 'won' };
  }

  // The host's ruling on a spoken answer.
  hostJudge(correct) {
    if (this.phase === 'answering') this.submitAnswer(this.clue.buzzedId, null, false, !!correct);
    else if (this.phase === 'dd-answer') this.submitAnswer(this.controllerId, null, false, !!correct);
  }

  submitAnswer(pid, text, timedOut, verdict) {
    const spoken = text === null;
    text = spoken ? null : String(text || '').slice(0, 80);
    const decide = () => (verdict !== undefined ? verdict : !timedOut && judge(text, [this.clue.a, ...this.clue.alt]));
    const shown = () => (spoken ? null : text || '(no answer)');
    if (this.phase === 'answering' && this.clue.buzzedId === pid) {
      const correct = decide();
      const p = this.players.get(pid);
      const v = this.clue.value;
      if (p) p.score += correct ? v : -v;
      this.clue.tried.push(pid);
      this.lastResult = { pid, answer: shown(), correct, delta: v, overridden: false };
      if (correct) {
        this.controllerId = pid;
        this.revealClue();
      } else {
        const remaining = this.order.filter((id) => this.isConnected(id) && !this.clue.tried.includes(id));
        if (remaining.length === 0) this.revealClue();
        else this.openBuzzers(T.rebuzzWindow);
      }
      this.touch();
      return;
    }
    if (this.phase === 'dd-answer' && this.controllerId === pid) {
      const correct = decide();
      const p = this.players.get(pid);
      const v = this.clue.wager;
      if (p) p.score += correct ? v : -v;
      this.lastResult = { pid, answer: shown(), correct, delta: v, overridden: false };
      this.revealClue();
      this.touch();
    }
  }

  ddWager(pid, amount) {
    if (this.phase !== 'dd-wager' || pid !== this.controllerId) return;
    const max = this.maxDDWager(pid);
    let w = Math.round(Number(amount));
    if (!Number.isFinite(w)) return;
    w = Math.max(5, Math.min(max, w));
    this.clue.wager = w;
    this.phase = 'dd-answer';
    this.setTimer(readingTime(this.clue.q) + (this.hostMode ? T.hostAnswer : T.ddAnswer), () => this.submitAnswer(pid, '', true));
    this.touch();
  }

  maxDDWager(pid) {
    const p = this.players.get(pid);
    return Math.max(p ? p.score : 0, 1000 * this.round);
  }

  endClue() {
    if (!this.clue) return;
    if (this.phase === 'answering') {
      this.submitAnswer(this.clue.buzzedId, '', true);
      return;
    }
    this.revealClue();
  }

  revealClue() {
    this.phase = 'reveal';
    this.setTimer(T.reveal, () => this.afterReveal());
    this.touch();
  }

  afterReveal() {
    this.clue = null;
    const b = this.board();
    const left = b.some((c) => c.clues.some((cl) => !cl.used));
    if (!left) {
      this.phase = 'round-end';
      this.clearTimer();
    } else {
      this.phase = 'board';
      this.clearTimer();
      // If whoever is in control left, give control to someone who is here.
      if (!this.isConnected(this.controllerId)) {
        const here = this.order.filter((id) => this.isConnected(id));
        if (here.length) this.controllerId = here[0];
      }
    }
    this.touch();
  }

  // Captain or TV moves things along.
  advance() {
    if (this.phase === 'round-end') {
      if (this.round === 1) {
        this.round = 2;
        // Lowest score picks first in round two.
        const sorted = this.order.slice().sort((a, b) => this.players.get(a).score - this.players.get(b).score);
        this.controllerId = sorted[0];
        this.phase = 'board';
        this.touch();
      } else {
        this.startFinal();
      }
    } else if (this.phase === 'reveal') {
      this.clearTimer();
      this.afterReveal();
    } else if (this.phase === 'final-wager') {
      this.beginFinalClue();
    } else if (this.phase === 'final-answer') {
      this.clearTimer();
      this.beginFinalReveal();
    } else if (this.phase === 'final-reveal') {
      this.finalStep();
    }
  }

  skipClue() {
    if (['reading', 'open', 'answering'].includes(this.phase)) {
      if (this.phase === 'answering') {
        // Treat as no answer for the buzzed player.
        this.submitAnswer(this.clue.buzzedId, '', true);
        if (this.phase !== 'reveal') this.revealClue();
      } else {
        this.revealClue();
      }
    } else if (this.phase === 'dd-wager' || this.phase === 'dd-answer') {
      if (this.phase === 'dd-wager') this.clue.wager = 0;
      this.revealClue();
    }
  }

  // Skip to the end of the current round (handy for short games).
  endRound() {
    const b = this.board();
    if (!b || !['board'].includes(this.phase)) return;
    b.forEach((c) => c.clues.forEach((cl) => { cl.used = true; }));
    this.phase = 'round-end';
    this.clearTimer();
    this.touch();
  }

  // Flip the last automatic judgment (typo or a generous call).
  override() {
    const r = this.lastResult;
    if (!r || this.phase.startsWith('final')) return;
    const p = this.players.get(r.pid);
    if (!p) return;
    const sign = r.correct ? -1 : 1;
    p.score += sign * 2 * r.delta;
    r.correct = !r.correct;
    r.overridden = !r.overridden;
    if (r.correct) {
      this.controllerId = r.pid;
      if (['open', 'reading', 'answering'].includes(this.phase)) this.revealClue();
    }
    this.touch();
  }

  // ---------- final round ----------
  startFinal() {
    this.round = 3;
    const eligible = this.order.filter((id) => this.players.get(id).score > 0);
    if (!this.finalClue || eligible.length === 0) {
      this.phase = 'gameover';
      this.clearTimer();
      this.touch();
      return;
    }
    this.final = {
      category: this.finalClue.category,
      q: this.finalClue.q,
      a: this.finalClue.a,
      alt: this.finalClue.alt,
      eligible,
      wagers: {},
      answers: {},
      results: {},
      revealOrder: [],
      revealIndex: -1,
    };
    this.phase = 'final-wager';
    this.clearTimer();
    this.touch();
  }

  finalWager(pid, amount) {
    if (this.phase !== 'final-wager' || !this.final.eligible.includes(pid)) return;
    const p = this.players.get(pid);
    let w = Math.round(Number(amount));
    if (!Number.isFinite(w)) return;
    w = Math.max(0, Math.min(p.score, w));
    this.final.wagers[pid] = w;
    this.touch();
    const waiting = this.final.eligible.filter((id) => this.isConnected(id) && !(id in this.final.wagers));
    if (waiting.length === 0) this.beginFinalClue();
  }

  beginFinalClue() {
    if (this.phase !== 'final-wager') return;
    for (const id of this.final.eligible) if (!(id in this.final.wagers)) this.final.wagers[id] = 0;
    this.phase = 'final-answer';
    this.setTimer(T.finalAnswer, () => this.beginFinalReveal());
    this.touch();
  }

  finalAnswer(pid, text) {
    if (this.phase !== 'final-answer' || !this.final.eligible.includes(pid)) return;
    if (pid in this.final.answers) return; // locked in already
    this.final.answers[pid] = String(text || '').slice(0, 80);
    this.touch();
    const waiting = this.final.eligible.filter((id) => this.isConnected(id) && !(id in this.final.answers));
    if (waiting.length === 0) {
      // Short pause so the last player sees "locked in" before the reveal.
      this.setTimer(1500, () => this.beginFinalReveal());
    }
  }

  beginFinalReveal() {
    if (this.phase !== 'final-answer') return;
    const f = this.final;
    for (const id of f.eligible) {
      const ans = f.answers[id] || '';
      f.results[id] = { answer: ans || '(no answer)', correct: judge(ans, [f.a, ...f.alt]), shown: false, applied: false };
    }
    f.revealOrder = f.eligible.slice().sort((a, b) => this.players.get(a).score - this.players.get(b).score);
    f.revealIndex = -1;
    this.phase = 'final-reveal';
    this.finalStep();
  }

  finalStep() {
    const f = this.final;
    f.revealIndex++;
    if (f.revealIndex >= f.revealOrder.length) {
      this.phase = 'gameover';
      this.clearTimer();
      this.touch();
      return;
    }
    const id = f.revealOrder[f.revealIndex];
    const r = f.results[id];
    const p = this.players.get(id);
    r.shown = true;
    if (p && !r.applied) {
      p.score += r.correct ? f.wagers[id] : -f.wagers[id];
      r.applied = true;
    }
    this.setTimer(T.finalStep, () => this.finalStep());
    this.touch();
  }

  // Flip a final-round judgment for one player.
  finalOverride(pid) {
    if (!this.final || !['final-reveal', 'gameover'].includes(this.phase)) return;
    const r = this.final.results[pid];
    const p = this.players.get(pid);
    if (!r || !r.applied || !p) return;
    const w = this.final.wagers[pid];
    p.score += r.correct ? -2 * w : 2 * w;
    r.correct = !r.correct;
    r.overridden = !r.overridden;
    this.touch();
  }

  playAgain() {
    if (this.phase !== 'gameover') return;
    for (const p of this.players.values()) p.score = 0;
    this.phase = 'lobby';
    this.round = 0;
    this.clue = null;
    this.final = null;
    this.lastResult = null;
    this.clearTimer();
    this.touch();
  }

  // ---------- views ----------
  view(role, pid) {
    const showAnswer = this.phase === 'reveal';
    const b = this.board();
    const v = {
      code: this.code,
      phase: this.phase,
      round: this.round,
      now: Date.now(),
      deadline: this.deadline,
      duration: this.duration,
      captainId: this.captain(),
      hostMode: this.hostMode,
      hostName: this.hostName,
      hostConnected: this.hostConnections > 0,
      controllerId: this.controllerId,
      players: this.order.map((id) => {
        const p = this.players.get(id);
        return { id, name: p.name, score: p.score, color: p.color, connected: p.connections > 0 };
      }),
      board: b && b.map((c) => ({ name: c.name, clues: c.clues.map((cl) => ({ value: cl.value, used: cl.used })) })),
      clue: this.clue && {
        ci: this.clue.ci,
        ri: this.clue.ri,
        cat: this.clue.cat,
        value: this.clue.value,
        dd: this.clue.dd,
        wager: this.clue.wager,
        q: this.phase === 'dd-wager' ? null : this.clue.q,
        answer: showAnswer ? this.clue.a : null,
        buzzedId: this.clue.buzzedId,
        tried: this.clue.tried,
      },
      lastResult: this.lastResult,
    };
    if (this.phase === 'lobby') {
      v.packs = this.packs.map((pk) => ({ id: pk.id, title: pk.title, description: pk.description, count: pk.categories.length, selected: this.selectedPacks.has(pk.id) }));
      v.categoryCount = this.bank().categories.length;
    }
    if (this.final) {
      const f = this.final;
      const showQ = ['final-answer', 'final-reveal', 'gameover'].includes(this.phase);
      const done = ['final-reveal', 'gameover'].includes(this.phase);
      v.final = {
        category: f.category,
        q: showQ ? f.q : null,
        answer: done && (this.phase === 'gameover' || f.revealIndex >= 0) ? f.a : null,
        eligible: f.eligible,
        wagered: Object.keys(f.wagers),
        answered: Object.keys(f.answers),
        revealIndex: f.revealIndex,
        reveals: done
          ? f.revealOrder.slice(0, f.revealIndex + 1).map((id) => ({ id, ...f.results[id], wager: f.wagers[id] }))
          : [],
      };
    }
    if (role === 'player' && pid) {
      const p = this.players.get(pid);
      v.me = p ? {
        id: pid,
        score: p.score,
        isCaptain: this.captain() === pid,
        maxDD: this.phase === 'dd-wager' ? this.maxDDWager(pid) : null,
        finalWager: this.final ? this.final.wagers[pid] : undefined,
        finalAnswer: this.final ? this.final.answers[pid] : undefined,
      } : null;
    }
    if (role === 'host' && pid === this.hostId) {
      v.me = { id: pid, isHost: true, isCaptain: true, name: this.hostName };
      // Only the host's phone ever gets the answers ahead of time.
      v.secret = {
        q: this.clue ? this.clue.q : null,
        answer: this.clue ? this.clue.a : null,
        alt: this.clue ? this.clue.alt : [],
        finalAnswer: this.final ? this.final.a : null,
        finalAnswers: this.final && this.phase === 'final-answer' ? this.final.answers : null,
      };
    }
    return v;
  }
}

if (typeof module !== 'undefined' && module.exports) module.exports = { Game, T };
else window.BWGame = { Game, T };
})();
