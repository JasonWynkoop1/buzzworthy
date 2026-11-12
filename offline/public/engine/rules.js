(function () {
// Shared by the Node server (local mode) and the TV page (online mode).

// Turn a question pack file into the shape the game uses.
function normalizePack(id, data) {
  return {
    id,
    title: String(data.title || id),
    description: String(data.description || ''),
    selected: data.selected !== false,
    categories: (data.categories || []).filter((c) => c.name && Array.isArray(c.clues) && c.clues.length >= 5),
    finals: (data.finals || []).filter((fin) => fin.q && fin.a),
  };
}

const TV_ACTIONS = new Set(['judge', 'openNow', 'togglePack', 'start', 'pick', 'advance', 'skip', 'override', 'finalOverride', 'endRound', 'playAgain', 'kick']);
const CAPTAIN_ACTIONS = new Set(['togglePack', 'start', 'advance', 'skip', 'override', 'finalOverride', 'endRound', 'playAgain']);

function act(game, role, pid, body) {
  const g = game;
  const t = body.type;
  // The host's phone gets the same powers as the TV.
  if (role === 'player' && pid && pid === g.hostId) role = 'host';
  if (role === 'tv' || role === 'host') {
    if (!TV_ACTIONS.has(t) && t !== 'leaveHost') return { error: 'not allowed' };
  } else {
    if (!g.players.has(pid)) return { error: 'not in room' };
    if (CAPTAIN_ACTIONS.has(t) && g.captain() !== pid) return { error: 'captain only' };
  }
  switch (t) {
    case 'start': return g.start() || { ok: true };
    case 'togglePack': g.togglePack(String(body.pack)); break;
    case 'pick': {
      // The player in control picks. The captain can step in if the controller is offline.
      const allowed = role === 'tv' || role === 'host' || pid === g.controllerId || (pid === g.captainId && !g.isConnected(g.controllerId));
      if (!allowed) return { error: 'not your pick' };
      g.pick(Number(body.ci), Number(body.ri));
      break;
    }
    case 'buzz': return g.buzz(pid);
    case 'answer':
      if (g.hostMode) return { error: 'The host judges answers out loud.' };
      g.submitAnswer(pid, body.text, false);
      break;
    case 'judge': g.hostJudge(body.correct === true); break;
    case 'openNow': g.openNow(); break;
    case 'leaveHost': g.leaveHost(pid); break;
    case 'ddWager': g.ddWager(pid, body.amount); break;
    case 'finalWager': g.finalWager(pid, body.amount); break;
    case 'finalAnswer': g.finalAnswer(pid, body.text); break;
    case 'advance': g.advance(); break;
    case 'skip': g.skipClue(); break;
    case 'override': g.override(); break;
    case 'finalOverride': g.finalOverride(body.targetPid || body.pid); break;
    case 'endRound': g.endRound(); break;
    case 'playAgain': g.playAgain(); break;
    case 'kick': g.kick(body.pid); break;
    default: return { error: 'unknown action' };
  }
  return { ok: true };
}

const BWRules = { normalizePack, act };
if (typeof module !== 'undefined' && module.exports) module.exports = BWRules;
else window.BWRules = BWRules;
})();
