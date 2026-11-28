## The page-side bridge injected at document start.
##
## Protocol:
##   page -> app: {t:"call", id, k, method, args}
##                {t:"cancel", id, k}
##                {t:"jserror", k, message}
##   app -> page: window.__nimi._resolve(id, value)
##                window.__nimi._reject(id, message)
##                window.__nimi._chunk(id, chunk)
##                window.__nimi._event(name, payload)

const bridgeJs* = """
(function () {
  if (window.__nimi) return;
  var secret = "__NIMI_SECRET__";
  var token = "__NIMI_TOKEN__";
  var pending = new Map();
  var eventListeners = new Map();
  var next = 1;
  function postToHost(payload) {
    payload.k = token;
    window.webkit.messageHandlers.nimi.postMessage(secret + JSON.stringify(payload));
  }
  window.__nimi = {
    _resolve: function (id, value) {
      var p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      if (p.cleanup) p.cleanup();
      p.resolve(value);
    },
    _reject: function (id, message) {
      var p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      if (p.cleanup) p.cleanup();
      p.reject(new Error(message));
    },
    _chunk: function (id, chunk) {
      var p = pending.get(id);
      if (!p || !p.onChunk) return;
      try { p.onChunk(chunk); } catch (e) { console.error(e); }
    },
    _event: function (name, payload) {
      var list = eventListeners.get(name);
      if (!list) return;
      list.slice().forEach(function (fn) {
        try { fn(payload); } catch (e) { console.error(e); }
      });
    }
  };
  window.nimi = {
    call: function (method) {
      var args = Array.prototype.slice.call(arguments, 1);
      return new Promise(function (resolve, reject) {
        var id = next++;
        pending.set(id, {resolve: resolve, reject: reject});
        postToHost({t: "call", id: id, method: method, args: args});
      });
    },
    stream: function (method, options) {
      var opts = options || {};
      var args = Array.isArray(opts.args) ? opts.args : [];
      var onChunk = typeof opts.onChunk === "function" ? opts.onChunk : null;
      var signal = opts.signal || null;
      return new Promise(function (resolve, reject) {
        if (signal && signal.aborted) {
          reject(new Error("IPC call cancelled"));
          return;
        }
        var id = next++;
        var cleanup = null;
        if (signal && typeof signal.addEventListener === "function") {
          var onAbort = function () {
            if (pending.has(id)) {
              postToHost({t: "cancel", id: id});
            }
          };
          signal.addEventListener("abort", onAbort, {once: true});
          cleanup = function () {
            signal.removeEventListener("abort", onAbort);
          };
        }
        pending.set(id, {resolve: resolve, reject: reject, onChunk: onChunk, cleanup: cleanup});
        postToHost({t: "call", id: id, method: method, args: args});
      });
    },
    cancel: function (id) {
      postToHost({t: "cancel", id: id});
    },
    reportError: function (message) {
      postToHost({t: "jserror", message: String(message || "")});
    },
    on: function (name, fn) {
      var list = eventListeners.get(name) || [];
      list.push(fn);
      eventListeners.set(name, list);
      return function () {
        var i = list.indexOf(fn);
        if (i >= 0) list.splice(i, 1);
      };
    }
  };
  window.mygo = window.nimi;
})();
"""

# Kept for code that still asks for the old name.
const bridgeScript* = bridgeJs
