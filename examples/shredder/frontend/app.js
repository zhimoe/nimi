(() => {
  "use strict";
  const canvas = document.getElementById("stage");
  const gl = canvas.getContext("webgl", {
    alpha: false,
    antialias: true,
    premultipliedAlpha: false,
    preserveDrawingBuffer: true,
  });
  if (!gl) {
    document.body.insertAdjacentHTML(
      "beforeend",
      '<p style="position:fixed;bottom:24px;left:30px;color:#e17a55">' +
      "WebGL is unavailable on this machine.</p>");
    return;
  }

  const WIDTH = 260, HEIGHT = 190, LEAD = 24, SPEED = 175;
  const COUNT = 36, SEGMENTS = 24;
  const STEP = 1 / 120, GRAVITY = 700, DAMPING = 0.994;
  const stripW = WIDTH / COUNT;
  const segH = HEIGHT / SEGMENTS;
  const MAX_VERTS = COUNT * SEGMENTS * 6;

  let width = 0, height = 0, dpr = 1;
  let paper = null;
  let started = false;
  let last = 0;
  let lag = 0;
  let elapsed = 0;
  let frameCount = 0;
  const strips = Array.from({ length: COUNT }, () => ({ nodes: [] }));

  const VS = `
    attribute vec2 aPos;
    attribute vec2 aUV;
    uniform vec2 uRes;
    varying vec2 vUV;
    void main() {
      vec2 p = aPos / uRes;
      gl_Position = vec4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
      vUV = aUV;
    }`;
  const FS = `
    precision mediump float;
    varying vec2 vUV;
    uniform sampler2D uTex;
    uniform vec4 uColor;
    uniform float uSolid;
    void main() {
      vec4 c = uSolid > 0.5 ? uColor : texture2D(uTex, vUV);
      gl_FragColor = c;
    }`;

  function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(shader));
    }
    return shader;
  }

  const program = gl.createProgram();
  gl.attachShader(program, compile(gl.VERTEX_SHADER, VS));
  gl.attachShader(program, compile(gl.FRAGMENT_SHADER, FS));
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    throw new Error(gl.getProgramInfoLog(program));
  }
  gl.useProgram(program);
  const aPos = gl.getAttribLocation(program, "aPos");
  const aUV = gl.getAttribLocation(program, "aUV");
  const uRes = gl.getUniformLocation(program, "uRes");
  const uTex = gl.getUniformLocation(program, "uTex");
  const uColor = gl.getUniformLocation(program, "uColor");
  const uSolid = gl.getUniformLocation(program, "uSolid");
  const buffer = gl.createBuffer();
  let texture = null;
  const verts = new Float32Array(MAX_VERTS * 4);
  let vertCount = 0;

  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.max(1, Math.floor(width * dpr));
    canvas.height = Math.max(1, Math.floor(height * dpr));
    canvas.style.width = width + "px";
    canvas.style.height = height + "px";
    gl.viewport(0, 0, canvas.width, canvas.height);
  }

  function makePaper() {
    paper = document.createElement("canvas");
    paper.width = WIDTH;
    paper.height = HEIGHT;
    const p = paper.getContext("2d");
    p.fillStyle = "#ffffff";
    p.fillRect(0, 0, WIDTH, HEIGHT);
    p.fillStyle = "#222222";
    p.font = "bold 22px -apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif";
    p.textAlign = "center";
    p.textBaseline = "middle";
    p.fillText("Hello, Nimi", WIDTH / 2, HEIGHT / 2);
    p.strokeStyle = "#eeeeee";
    p.lineWidth = 1;
    p.strokeRect(0.5, 0.5, WIDTH - 1, HEIGHT - 1);

    texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA,
                  gl.UNSIGNED_BYTE, paper);
  }

  function reset(now) {
    for (const strip of strips) strip.nodes.length = 0;
    elapsed = 0;
    lag = 0;
    last = now;
    started = true;
  }

  function windAt(x, y, t) {
    const xWind = 280 * Math.sin(t * 1.8) +
      180 * Math.sin(y * 0.018 - t * 2.4) +
      70 * Math.sin(x * 0.025 + t * 3.1) +
      58 * Math.sin(x * 0.23 + t * 4.6);
    const yWind = 85 * Math.sin(x * 0.018 + y * 0.009 + t * 2.2);
    return [xWind, yWind];
  }

  function constrainAnchor(n, x, length) {
    const dx = n.x - x, dy = n.y;
    const d = Math.hypot(dx, dy);
    if (d < 0.0001) {
      n.x = x;
      n.y = length;
      return;
    }
    n.x = x + dx * length / d;
    n.y = dy * length / d;
  }

  function constrainPair(a, b, length) {
    let dx = b.x - a.x, dy = b.y - a.y;
    let d = Math.hypot(dx, dy);
    if (d < 0.0001) {
      dx = 0;
      dy = 1;
      d = 1;
    }
    const correction = (d - length) / (2 * d);
    a.x += dx * correction;
    a.y += dy * correction;
    b.x -= dx * correction;
    b.y -= dy * correction;
  }

  function step(dt) {
    elapsed += dt;
    const top = -HEIGHT - LEAD + SPEED * elapsed;
    const attached = top < 0;
    for (let i = 0; i < COUNT; i++) {
      const line = strips[i];
      const center = (i + 0.5) * WIDTH / COUNT;
      while (line.nodes.length < SEGMENTS + 1 &&
             top + HEIGHT - line.nodes.length * segH >= 0) {
        const flutter = Math.sin(i * 1.71 + line.nodes.length * 0.53) * 30;
        line.nodes.push({
          x: center,
          y: 0,
          px: center - flutter * dt,
          py: -SPEED * dt,
        });
      }
      for (const n of line.nodes) {
        const vx = (n.x - n.px) * DAMPING;
        const vy = (n.y - n.py) * DAMPING;
        n.px = n.x;
        n.py = n.y;
        let [wx, wy] = windAt(n.x, n.y, elapsed);
        if (!attached) {
          wx += Math.sin(elapsed * 3.1 + i * 0.9) * 160 +
            Math.sin(elapsed * 7.7 + i * 2.3) * 55;
        }
        n.x += vx + wx * dt * dt;
        n.y += vy + (GRAVITY + wy) * dt * dt;
      }
      for (let pass = 0; pass < 7; pass++) {
        if (attached && line.nodes.length > 0) {
          const lastNode = line.nodes[line.nodes.length - 1];
          const tail = Math.min(segH, Math.max(
            0, top + HEIGHT - (line.nodes.length - 1) * segH));
          constrainAnchor(lastNode, center, tail);
        }
        for (let k = line.nodes.length - 1; k > 0; k--) {
          constrainPair(line.nodes[k], line.nodes[k - 1], segH);
        }
      }
    }
  }

  function advance(now) {
    if (!started) {
      reset(now);
      return;
    }
    const dt = Math.min(Math.max(now - last, 0), 0.12);
    last = now;
    lag += dt;
    while (lag >= STEP) {
      step(STEP);
      lag -= STEP;
    }
  }

  function pushVertex(x, y, u, v) {
    const at = vertCount * 4;
    verts[at] = x;
    verts[at + 1] = y;
    verts[at + 2] = u;
    verts[at + 3] = v;
    vertCount++;
  }

  function pushQuad(x0, y0, x1, y1, u0, v0, u1, v1) {
    pushVertex(x0, y0, u0, v0);
    pushVertex(x1, y0, u1, v0);
    pushVertex(x1, y1, u1, v1);
    pushVertex(x0, y0, u0, v0);
    pushVertex(x1, y1, u1, v1);
    pushVertex(x0, y1, u0, v1);
  }

  function flush(textured) {
    if (vertCount === 0) return;
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, verts.subarray(0, vertCount * 4),
                  gl.DYNAMIC_DRAW);
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 16, 0);
    gl.enableVertexAttribArray(aUV);
    gl.vertexAttribPointer(aUV, 2, gl.FLOAT, false, 16, 8);
    gl.uniform1f(uSolid, textured ? 0 : 1);
    if (textured) {
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.uniform1i(uTex, 0);
    }
    gl.drawArrays(gl.TRIANGLES, 0, vertCount);
    vertCount = 0;
  }

  function draw(now) {
    advance(now / 1000);
    frameCount++;
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0.125, 0.125, 0.125, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    const slot = height * 0.49;
    const stageX = width / 2;
    const paperX = stageX - WIDTH / 2;
    const top = Math.min(slot, slot - HEIGHT - LEAD + SPEED * elapsed);
    gl.useProgram(program);
    gl.uniform2f(uRes, width, height);
    gl.uniform4f(uColor, 0, 0, 0, 1);

    // The part of the sheet that has not entered the slot yet.
    if (top < slot) {
      gl.enable(gl.SCISSOR_TEST);
      gl.scissor(0, Math.floor(dpr * (height - slot)),
                 Math.ceil(dpr * width), Math.ceil(dpr * slot));
      pushQuad(paperX, top, paperX + WIDTH, top + HEIGHT,
               0, 0, 1, 1);
      flush(true);
      gl.disable(gl.SCISSOR_TEST);
    }

    // Shredded ribbons below the slot. Shared edge vertices mean there are
    // no seams between the 24 segments of each strip.
    gl.enable(gl.SCISSOR_TEST);
    gl.scissor(0, 0, Math.ceil(dpr * width),
               Math.ceil(dpr * (height - slot)));
    for (let i = 0; i < COUNT; i++) {
      const nodes = strips[i].nodes;
      if (nodes.length < 2) continue;
      const half = stripW * 0.41;
      const left = [];
      const right = [];
      for (let k = 0; k < nodes.length; k++) {
        const before = nodes[Math.max(0, k - 1)];
        const after = nodes[Math.min(nodes.length - 1, k + 1)];
        let tx = after.x - before.x, ty = after.y - before.y;
        const tl = Math.hypot(tx, ty) || 1;
        tx /= tl;
        ty /= tl;
        left.push([paperX + nodes[k].x - ty * half,
                   slot + nodes[k].y + tx * half]);
        right.push([paperX + nodes[k].x + ty * half,
                    slot + nodes[k].y - tx * half]);
      }
      const u0 = i / COUNT;
      const u1 = (i + 1) / COUNT;
      for (let k = 0; k < nodes.length - 1; k++) {
        const v0 = 1 - k / SEGMENTS;
        const v1 = 1 - (k + 1) / SEGMENTS;
        const l0 = left[k], r0 = right[k];
        const l1 = left[k + 1], r1 = right[k + 1];
        pushVertex(l0[0], l0[1], u0, v0);
        pushVertex(r0[0], r0[1], u1, v0);
        pushVertex(r1[0], r1[1], u1, v1);
        pushVertex(l0[0], l0[1], u0, v0);
        pushVertex(r1[0], r1[1], u1, v1);
        pushVertex(l1[0], l1[1], u0, v1);
      }
    }
    flush(true);
    gl.disable(gl.SCISSOR_TEST);

    // Slot hardware.
    const slotW = WIDTH + 110;
    const sx = stageX - slotW / 2;
    gl.uniform4f(uColor, 0.333, 0.333, 0.333, 1);
    pushQuad(sx, slot - 10, sx + slotW, slot + 10, 0, 0, 0, 0);
    flush(false);
    gl.uniform4f(uColor, 0.067, 0.067, 0.067, 1);
    pushQuad(sx + 14, slot - 2, sx + slotW - 14, slot + 2,
             0, 0, 0, 0);
    flush(false);
  }

  function loop(now) {
    try {
      draw(now);
    } catch (e) {
      console.error(e);
    }
    requestAnimationFrame(loop);
  }

  window.addEventListener("resize", resize);
  window.addEventListener("click", () => reset(performance.now() / 1000));
  resize();
  makePaper();
  requestAnimationFrame(loop);

  if (location.search.includes("smoke")) {
    setTimeout(async () => {
      try {
        reset(0);
        for (let i = 0; i < 60; i++) step(STEP);
        last = performance.now() / 1000;
        draw(performance.now());
        await window.nimi.call("Shell.report",
          "shredder frames: " + frameCount);
        await window.nimi.call("Shell.snapshot", canvas.toDataURL("image/png"));
        await window.nimi.call("Shell.quit");
      } catch (e) {
        await window.nimi.call("Shell.report", "shredder error: " + e.message);
        await window.nimi.call("Shell.quit");
      }
    }, 1700);
  }
})();
