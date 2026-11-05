(async function () {
  const scheme = document.getElementById("scheme");
  const path = document.getElementById("path");
  const ipc = document.getElementById("ipc");
  scheme.textContent = location.protocol.replace(":", "");
  path.textContent = location.pathname;

  try {
    const text = await window.nimi.call("Greeter.greet", "WKURLSchemeHandler");
    ipc.textContent = text;
    if (location.search.includes("smoke")) {
      await window.nimi.call("Shell.report", "protocol: " + text);
      await window.nimi.call("Shell.quit");
    }
  } catch (error) {
    ipc.textContent = "error: " + error.message;
    if (location.search.includes("smoke")) {
      await window.nimi.call("Shell.report", "protocol error: " + error.message);
      await window.nimi.call("Shell.quit");
    }
  }
})();
