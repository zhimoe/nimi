## The page-side bridge injected at document start.
##
## M1 protocol (a subset of MyGo's):
##   page -> app: {t:"call", id, method, args}
##   app -> page: window.__nimi._resolve(id, value)
##                window.__nimi._reject(id, message)
##
## Events and secret/token checks are implemented; channels and batching remain planned.

const bridgeJs* = """
(function () {
  if (window.__nimi) return;
  var secret = "__NIMI_SECRET__";
  var token = "__NIMI_TOKEN__";
  var pending = new Map();
  var eventListeners = new Map();
  var next = 1;
  window.__nimi = {
    _resolve: function (id, value) {
      var p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      p.resolve(value);
    },
    _reject: function (id, message) {
      var p = pending.get(id);
      if (!p) return;
      pending.delete(id);
      p.reject(new Error(message));
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
        window.webkit.messageHandlers.nimi.postMessage(secret + JSON.stringify({
          t: "call", id: id, k: token, method: method, args: args
        }));
      });
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
  // Compatibility alias for code written against MyGo.
  window.mygo = window.nimi;
})();
"""

# Kept for code that still asks for the old name.
const bridgeScript* = bridgeJs
