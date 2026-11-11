// Gives the game engine the few browser things it expects (window, timers,
// console) inside JavaScriptCore. Timers are run by the app's run loop.
var window = this;
var console = { log: function () { __native.log(Array.prototype.join.call(arguments, ' ')); } };
console.error = console.warn = console.log;
var __timers = {};
var __timerId = 0;
function setTimeout(fn, ms) {
  var id = ++__timerId;
  __timers[id] = fn;
  __native.schedule(id, Number(ms) || 0, false);
  return id;
}
function setInterval(fn, ms) {
  var id = ++__timerId;
  __timers[id] = fn;
  __native.schedule(id, Math.max(10, Number(ms) || 0), true);
  return id;
}
function clearTimeout(id) {
  if (!id || !__timers[id]) return;
  delete __timers[id];
  __native.cancel(id);
}
var clearInterval = clearTimeout;
function __fire(id, repeat) {
  var fn = __timers[id];
  if (!fn) return;
  if (!repeat) delete __timers[id];
  fn();
}
