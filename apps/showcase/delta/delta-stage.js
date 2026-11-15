/* OpenNI 三角洲专题 — 自研 WebGL2 氛围层
 * 设计依据见 kpr-shader-study：图像平面 + 遮罩/模糊过渡 + 平滑滚动。
 * 本文件为独立实现：全屏图像调色、噪声擦除、尘粒、扫描与操作员层合成。
 */

const VERT = `#version 300 es
in vec2 aPos;
out vec2 vUv;
void main(){ vUv = aPos * 0.5 + 0.5; gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
in vec2 vUv;
out vec4 outColor;

uniform sampler2D uPlateFrom;
uniform sampler2D uPlateTo;
uniform sampler2D uOperator;
uniform vec2 uFromSize;
uniform vec2 uToSize;
uniform vec4 uOpRect;
uniform vec2 uRes;
uniform float uTime;
uniform float uProgress;
uniform float uPlateMix;
uniform float uOperatorReveal;
uniform float uOperatorAlpha;
uniform float uDust;
uniform float uZoom;
uniform float uScanActive;
uniform float uScanPos;
uniform float uVignette;
uniform float uGrain;
uniform float uReduce;
uniform vec2 uPan;
uniform vec3 uTint;

float hash21(vec2 p){
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float vnoise(vec2 p){
  vec2 i = floor(p); vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p){
  float v = 0.0; float a = 0.55;
  for (int i = 0; i < 4; i++){ v += a * vnoise(p); p = p * 2.03 + 11.7; a *= 0.5; }
  return v;
}
vec2 coverUv(vec2 uv, vec2 texSize, vec2 res){
  float viewRatio = res.x / res.y;
  float texRatio = texSize.x / texSize.y;
  vec2 scale = vec2(1.0);
  if (viewRatio > texRatio) { scale.y = texRatio / viewRatio; }
  else { scale.x = viewRatio / texRatio; }
  return (uv - 0.5) * scale + 0.5;
}
vec3 gradeColor(vec3 c){
  c = max(c, vec3(0.0));
  c = mix(c, c * c * (3.0 - 2.0 * c), 0.22);
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  vec3 shadow = vec3(0.021, 0.038, 0.031);
  vec3 bone = vec3(0.96, 0.925, 0.845);
  vec3 duo = mix(shadow, bone, smoothstep(0.0, 1.0, l));
  c = mix(c, duo, 0.3);
  float hi = smoothstep(0.5, 0.94, l) * (1.0 - smoothstep(0.93, 1.0, l));
  c += vec3(0.085, 0.125, 0.02) * hi;
  c *= uTint;
  c = pow(c, vec3(0.98, 0.99, 1.02));
  return c;
}
vec3 samplePlate(sampler2D tex, vec2 uv, vec2 texSize, float zoom){
  vec2 cuv = coverUv(uv, texSize, uRes);
  cuv = (cuv - 0.5) / zoom + 0.5 + uPan;
  float ca = 0.0008 * (0.25 + length(uv - 0.5));
  float r = texture(tex, cuv + vec2(ca, 0.0)).r;
  vec4 mid = texture(tex, cuv);
  float b = texture(tex, cuv - vec2(ca, 0.0)).b;
  return vec3(r, mid.g, b);
}
float embers(vec2 uv, float layer){
  float acc = 0.0;
  float aspect = uRes.x / uRes.y;
  for (int i = 0; i < 12; i++){
    float fi = float(i) + layer * 12.0;
    float sp = 0.018 + 0.05 * hash21(vec2(fi, 1.7));
    float x = hash21(vec2(fi, 2.3)) + 0.012 * sin(uTime * 0.35 + fi * 1.7);
    float y = fract(hash21(vec2(fi, 3.1)) - uTime * sp * (layer * 0.5 + 0.7));
    vec2 p = vec2(x, y);
    float d = length((uv - p) * vec2(aspect, 1.0) * 1.6);
    float size = 0.0012 + 0.0034 * hash21(vec2(fi, 4.2)) * (1.0 + layer * 0.4);
    float glow = smoothstep(size * 3.2, 0.0, d) * 0.16 + smoothstep(size, 0.0, d) * 0.85;
    acc += glow * (0.3 + 0.7 * hash21(vec2(fi, 5.5)));
  }
  return acc;
}
void main(){
  vec2 suv = vec2(vUv.x, 1.0 - vUv.y); // 屏幕坐标：左上为 0
  float zoom = uZoom + uProgress * 0.06;
  vec3 colA = samplePlate(uPlateFrom, suv, uFromSize, zoom);
  vec3 colB = samplePlate(uPlateTo, suv, uToSize, zoom);
  vec3 col = colA;

  if (uPlateMix < 0.999){
    float n = fbm(suv * vec2(2.7, 3.4) + vec2(0.0, uTime * 0.015));
    float field = n * 0.72 + (1.0 - suv.y) * 0.42;
    float mask = smoothstep(uPlateMix - 0.2, uPlateMix + 0.2, field);
    col = mix(colA, colB, mask);
    float edge = 1.0 - smoothstep(0.0, 0.085, abs(field - uPlateMix));
    col += vec3(0.62, 0.78, 0.36) * edge * 0.16;
  }

  col = gradeColor(col);

  if (uOperatorAlpha > 0.001){
    vec2 opUv = (suv - uOpRect.xy) / max(uOpRect.zw - uOpRect.xy, vec2(0.0001));
    if (opUv.x > 0.0 && opUv.x < 1.0 && opUv.y > 0.0 && opUv.y < 1.0){
      vec4 op = texture(uOperator, opUv);
      float reveal = smoothstep(0.0, 1.0, uOperatorReveal * 1.55 - (1.0 - suv.y) * 0.42 - fbm(suv * 4.0) * 0.24);
      vec3 opCol = gradeColor(op.rgb) * 1.06;
      float edgeGlow = smoothstep(0.55, 0.0, op.a) * 0.04;
      col = mix(col, opCol + vec3(0.55, 0.72, 0.3) * edgeGlow, op.a * reveal * uOperatorAlpha);
    }
  }

  vec3 dustCol = vec3(0.83, 0.9, 0.68);
  col += dustCol * (embers(suv, 0.0) * 0.55 + embers(suv, 1.0) * 0.3) * uDust * (1.0 - uReduce * 0.35);

  if (uScanActive > 0.5){
    vec2 g = suv * vec2(uRes.x / uRes.y, 1.0) * 9.0;
    float lx = min(fract(g.x), 1.0 - fract(g.x));
    float ly = min(fract(g.y), 1.0 - fract(g.y));
    float grid = smoothstep(0.018, 0.0, min(lx, ly)) * 0.055;
    float sweep = exp(-pow((suv.y - uScanPos) * 34.0, 2.0));
    float trail = smoothstep(uScanPos + 0.12, uScanPos, suv.y) * 0.05;
    col += vec3(0.78, 0.92, 0.5) * (grid + sweep * 0.34 + trail);
    col += vec3(0.9, 1.0, 0.7) * smoothstep(0.004, 0.0, abs(suv.y - uScanPos)) * 0.5;
  }

  float vig = 1.0 - smoothstep(0.42, 0.92, length((suv - 0.5) * vec2(1.02, 1.24)));
  col *= mix(1.0, vig, uVignette);
  float scanl = 0.5 + 0.5 * sin(suv.y * uRes.y * 1.12);
  col *= 1.0 - scanl * 0.02 * (1.0 - uReduce);
  float grain = hash21(suv * uRes * 0.75 + fract(uTime) * 173.0);
  col += (grain - 0.5) * uGrain;
  col += (hash21(suv * uRes + 7.0) - 0.5) / 255.0;
  outColor = vec4(col, 1.0);
}`;

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const ease = (t) => 1 - Math.pow(1 - clamp(t, 0, 1), 3);

const TEX_MAX = 1920;

export function createDeltaStage(canvas, { onFallback } = {}) {
  const gl = canvas.getContext('webgl2', {
    alpha: false,
    antialias: false,
    depth: false,
    stencil: false,
    powerPreference: 'high-performance',
    preserveDrawingBuffer: false,
  });
  if (!gl) {
    onFallback?.('WebGL2 不可用');
    return null;
  }

  function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
      console.error('delta-stage shader', gl.getShaderInfoLog(shader));
      gl.deleteShader(shader);
      return null;
    }
    return shader;
  }
  const vs = compile(gl.VERTEX_SHADER, VERT);
  const fs = compile(gl.FRAGMENT_SHADER, FRAG);
  if (!vs || !fs) {
    onFallback?.('着色器编译失败');
    return null;
  }
  const program = gl.createProgram();
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    console.error('delta-stage link', gl.getProgramInfoLog(program));
    onFallback?.('着色器链接失败');
    return null;
  }
  gl.useProgram(program);

  const buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  const aPos = gl.getAttribLocation(program, 'aPos');
  gl.enableVertexAttribArray(aPos);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

  const U = {};
  for (const name of ['uPlateFrom', 'uPlateTo', 'uOperator', 'uFromSize', 'uToSize', 'uOpRect', 'uRes', 'uTime', 'uProgress', 'uPlateMix', 'uOperatorReveal', 'uOperatorAlpha', 'uDust', 'uZoom', 'uScanActive', 'uScanPos', 'uVignette', 'uGrain', 'uReduce', 'uPan', 'uTint']) {
    U[name] = gl.getUniformLocation(program, name);
  }

  const imageCache = new Map();
  const textures = new Map();

  function makeTexture(source, w, h) {
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return { tex, w, h };
  }

  async function loadTexture(url) {
    if (textures.has(url)) return textures.get(url);
    if (!imageCache.has(url)) {
      imageCache.set(url, new Promise((resolve, reject) => {
        const img = new Image();
        img.decoding = 'async';
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error(`纹理加载失败: ${url}`));
        img.src = url;
      }));
    }
    const img = await imageCache.get(url);
    if (textures.has(url)) return textures.get(url);
    const scale = Math.min(1, TEX_MAX / Math.max(img.naturalWidth, img.naturalHeight));
    const w = Math.max(1, Math.round(img.naturalWidth * scale));
    const h = Math.max(1, Math.round(img.naturalHeight * scale));
    let source = img;
    if (scale < 1) {
      try {
        source = await createImageBitmap(img, { resizeWidth: w, resizeHeight: h, resizeQuality: 'high' });
      } catch (error) {
        const c = document.createElement('canvas');
        c.width = w; c.height = h;
        c.getContext('2d').drawImage(img, 0, 0, w, h);
        source = c;
      }
    }
    const entry = makeTexture(source, w, h);
    textures.set(url, entry);
    return entry;
  }

  const state = {
    from: null,
    to: null,
    fromUrl: '',
    toUrl: '',
    mix: 1,
    mixTarget: 1,
    operator: null,
    opRect: [0.36, -0.1, 1.06, 1.02],
    opTarget: [0.36, -0.1, 1.06, 1.02],
    time: 0,
    values: { progress: 0, zoom: 1.03, panX: 0, panY: 0, dust: 0.7, reveal: 0, opAlpha: 0, scanActive: 0, scanPos: 0, vignette: 0.72, grain: 0.05, reduce: 0 },
    targets: { progress: 0, zoom: 1.03, panX: 0, panY: 0, dust: 0.7, reveal: 0, opAlpha: 0, scanActive: 0, scanPos: 0, vignette: 0.72, grain: 0.05, reduce: 0 },
    tint: [1, 1, 1],
    tintCurrent: [1, 1, 1],
    operatorUrl: '',
    ready: false,
  };

  let dpr = 1;
  let raf = 0;
  let last = 0;
  let paused = false;
  let pendingRender = false;

  function resize() {
    dpr = clamp(window.devicePixelRatio || 1, 1, window.innerWidth < 900 ? 1.35 : 1.7);
    const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
    const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
    gl.viewport(0, 0, canvas.width, canvas.height);
    pendingRender = true;
    if (!raf) renderOnce();
  }

  async function setPlate(url) {
    if (!url || url === state.toUrl) return;
    const previousUrl = state.toUrl;
    try {
      const entry = await loadTexture(url);
      const previous = previousUrl ? textures.get(previousUrl) : null;
      state.from = previous || entry;
      state.fromUrl = previous ? previousUrl : url;
      state.to = entry;
      state.toUrl = url;
      state.mix = previous ? 0 : 1;
      state.mixTarget = 1;
      state.ready = true;
      document.body.classList.remove('stage-booting');
      pendingRender = true;
      if (!raf) renderOnce();
    } catch (error) {
      console.warn(error);
    }
  }

  async function setOperator(url) {
    if (!url || url === state.operatorUrl) return;
    try {
      state.operator = await loadTexture(url);
      state.operatorUrl = url;
      pendingRender = true;
      if (!raf) renderOnce();
    } catch (error) {
      console.warn(error);
    }
  }

  function setOperatorBox(box, fit = 'cover', anchor = 'rb') {
    // box: {x,y,w,h} 像素（屏幕坐标，左上原点）；fit: cover/contain；anchor: rb/center
    const op = state.operator;
    if (!op) return;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const scale = fit === 'contain' ? Math.min(box.w / op.w, box.h / op.h) : Math.max(box.w / op.w, box.h / op.h);
    const texW = op.w * scale;
    const texH = op.h * scale;
    const x1 = (box.x + box.w) / vw;
    const y1 = (box.y + box.h) / vh;
    const x0 = (anchor === 'center' ? box.x + (box.w - texW) / 2 : box.x + box.w - texW) / vw;
    const y0 = (box.y + box.h - texH) / vh;
    state.opTarget = [x0, y0, x1, y1];
    if (!raf) renderOnce();
  }

  function setScene(scene) {
    const t = state.targets;
    if (scene.progress !== undefined) t.progress = scene.progress;
    if (scene.zoom !== undefined) t.zoom = scene.zoom;
    if (scene.panX !== undefined) t.panX = scene.panX;
    if (scene.panY !== undefined) t.panY = scene.panY;
    if (scene.dust !== undefined) t.dust = scene.dust;
    if (scene.reveal !== undefined) t.reveal = scene.reveal;
    if (scene.opAlpha !== undefined) t.opAlpha = scene.opAlpha;
    if (scene.scanActive !== undefined) t.scanActive = scene.scanActive;
    if (scene.scanPos !== undefined) t.scanPos = scene.scanPos;
    if (scene.vignette !== undefined) t.vignette = scene.vignette;
    if (scene.grain !== undefined) t.grain = scene.grain;
    if (scene.reduce !== undefined) t.reduce = scene.reduce;
    if (scene.tint) state.tint = scene.tint;
    if (scene.opBox) setOperatorBox(scene.opBox, scene.opBoxFit, scene.opBoxAnchor);
  }

  function smooth(dt) {
    const staticMode = state.targets.reduce >= 0.5;
    const a = staticMode ? 1 : 1 - Math.exp(-4.2 * dt);
    for (const key of Object.keys(state.values)) {
      state.values[key] = lerp(state.values[key], state.targets[key], a);
    }
    state.mix = staticMode ? state.mixTarget : lerp(state.mix, state.mixTarget, 1 - Math.exp(-3.2 * dt));
    const opA = staticMode ? 1 : 1 - Math.exp(-4.0 * dt);
    state.opRect = state.opRect.map((v, i) => lerp(v, state.opTarget[i], opA));
    state.tintCurrent = state.tintCurrent.map((v, i) => lerp(v, state.tint[i], staticMode ? 1 : 1 - Math.exp(-2.6 * dt)));
  }

  function renderOnce() {
    if (raf) return;
    raf = 1;
    const now = performance.now();
    const dt = last ? Math.min(0.05, (now - last) / 1000) : 0.016;
    last = now;
    if (state.targets.reduce < 0.5) state.time += dt;
    smooth(dt);
    gl.useProgram(program);
    const v = state.values;
    const from = state.from || state.to;
    const to = state.to || state.from;
    if (!from || !to) { raf = 0; return; }
    gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, from.tex); gl.uniform1i(U.uPlateFrom, 0);
    gl.activeTexture(gl.TEXTURE1); gl.bindTexture(gl.TEXTURE_2D, to.tex); gl.uniform1i(U.uPlateTo, 1);
    gl.uniform2f(U.uFromSize, from.w, from.h);
    gl.uniform2f(U.uToSize, to.w, to.h);
    gl.uniform1f(U.uPlateMix, ease(state.mix));
    if (state.operator) {
      gl.activeTexture(gl.TEXTURE2); gl.bindTexture(gl.TEXTURE_2D, state.operator.tex); gl.uniform1i(U.uOperator, 2);
      gl.uniform4f(U.uOpRect, state.opRect[0], state.opRect[1], state.opRect[2], state.opRect[3]);
      gl.uniform1f(U.uOperatorReveal, v.reveal);
      gl.uniform1f(U.uOperatorAlpha, v.opAlpha);
    } else {
      gl.uniform4f(U.uOpRect, 0, 0, 0, 0);
      gl.uniform1f(U.uOperatorReveal, 0);
      gl.uniform1f(U.uOperatorAlpha, 0);
    }
    gl.uniform2f(U.uRes, canvas.width, canvas.height);
    gl.uniform1f(U.uTime, state.time);
    gl.uniform1f(U.uProgress, v.progress);
    gl.uniform1f(U.uDust, v.dust);
    gl.uniform1f(U.uZoom, v.zoom);
    gl.uniform1f(U.uScanActive, v.scanActive);
    gl.uniform1f(U.uScanPos, v.scanPos);
    gl.uniform1f(U.uVignette, v.vignette);
    gl.uniform1f(U.uGrain, v.grain);
    gl.uniform1f(U.uReduce, v.reduce);
    gl.uniform2f(U.uPan, v.panX, v.panY);
    gl.uniform3f(U.uTint, state.tintCurrent[0], state.tintCurrent[1], state.tintCurrent[2]);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    raf = 0;
  }

  function loop(now) {
    if (paused) { raf = 0; return; }
    renderOnce();
    raf = requestAnimationFrame(loop);
    void now;
  }

  function start() {
    if (raf) return;
    paused = false;
    raf = requestAnimationFrame(loop);
  }
  function stop() {
    paused = true;
    cancelAnimationFrame(raf);
    raf = 0;
  }

  const onVisibility = () => {
    if (document.hidden) stop();
    else if (state.values.reduce < 0.5) start();
  };
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('resize', resize);
  resize();

  return {
    setPlate,
    setOperator,
    setOperatorBox,
    setScene,
    start,
    stop,
    resize,
    render: renderOnce,
    get ready() { return state.ready; },
    get textureInfo() { return { from: state.fromUrl, to: state.toUrl, mix: state.mix }; },
    getDebug() {
      return {
        time: state.time,
        mix: state.mix,
        mixTarget: state.mixTarget,
        values: { ...state.values },
        targets: { ...state.targets },
        opRect: [...state.opRect],
        operatorLoaded: Boolean(state.operator),
        tint: [...state.tintCurrent],
      };
    },
    destroy() {
      stop();
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('resize', resize);
      for (const t of textures.values()) gl.deleteTexture(t.tex);
      gl.deleteProgram(program);
    },
  };
}
