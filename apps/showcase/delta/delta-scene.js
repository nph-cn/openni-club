/* OpenNI 三角洲行动 · 战地档案 — Three.js 3D 舞台
 * 参考 KPR 的渲染语言（透视相机 + 分层图像平面 + 遮罩显影 + 平滑滚动 + 逐字排版），
 * 代码与素材均为本项目独立实现；参数是本项目为三角洲素材做的改编值，不是 KPR 原值。
 */
import * as THREE from '../vendor/three.module.min.js';

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const damp = (current, target, lambda, dt) => current + (target - current) * (1 - Math.exp(-lambda * dt));
const smoothstep = (a, b, x) => {
  const t = clamp((x - a) / (b - a || 1), 0, 1);
  return t * t * (3 - 2 * t);
};

const CAMERA_KEYS = {
  hero: { a: { pos: [0.1, 0.22, 8.9], look: [0, 0.05, -3.0] }, b: { pos: [0.22, 0.12, 8.1], look: [0, 0.0, -3.4] } },
  modes: { a: { pos: [0.55, 0.04, 7.9], look: [0, 0, -4.2] }, b: { pos: [0.2, 0.02, 7.4], look: [0, 0, -4.35] } },
  terrain: { a: { pos: [-0.1, 2.4, 6.9], look: [0, -0.6, -2.2] }, b: { pos: [0.7, 2.2, 7.0], look: [0.1, -0.5, -2.2] } },
  squad: { a: { pos: [-0.8, 0.3, 7.3], look: [-0.7, 0.05, -0.3] }, b: { pos: [0.8, 0.24, 7.1], look: [0.7, 0.03, -0.3] } },
  deploy: { a: { pos: [0.45, 0.16, 8.4], look: [0, 0, -3.2] }, b: { pos: [0.12, 0.08, 7.6], look: [0, -0.05, -3.3] } },
};

const POST_VERT = `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;
const POST_FRAG = `
precision highp float;
uniform sampler2D tDiffuse;
uniform vec2 uRes;
uniform float uTime;
uniform float uEnter;
uniform float uVignette;
uniform float uGrain;
uniform float uChroma;
varying vec2 vUv;

float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

void main(){
  vec2 uv = vUv;
  float r2 = length(uv - 0.5);
  vec2 ca = (uv - 0.5) * r2 * uChroma;
  vec3 col;
  col.r = texture2D(tDiffuse, uv + ca).r;
  col.g = texture2D(tDiffuse, uv).g;
  col.b = texture2D(tDiffuse, uv - ca).b;

  float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
  col = mix(col, vec3(l), 0.1);
  col = max(col, vec3(0.0));
  col = pow(col, vec3(1.02, 0.99, 0.96));
  col = mix(vec3(0.008, 0.011, 0.01), vec3(1.05, 1.0, 0.9), col);
  col += vec3(0.028, 0.045, 0.008) * smoothstep(0.5, 0.92, l);
  col *= 1.0 + (l - 0.5) * 0.1;

  float vig = 1.0 - smoothstep(0.35, 0.95, r2 * 1.25);
  col *= mix(1.0, vig, uVignette);

  float grain = hash(uv * uRes * 0.72 + fract(uTime) * 173.0);
  col += (grain - 0.5) * uGrain;
  col *= 1.0 - 0.014 * (0.5 + 0.5 * sin(uv.y * uRes.y * 1.12));
  col += (hash(uv * uRes + 7.0) - 0.5) / 255.0;
  col *= uEnter;
  gl_FragColor = vec4(pow(max(col, 0.0), vec3(1.0 / 2.2)), 1.0);
}`;

const PLANE_VERT = `varying vec2 vUv; void main(){ vUv = uv; vec4 mv = modelViewMatrix * vec4(position, 1.0); gl_Position = projectionMatrix * mv; }`;

function planeFragment({ rounded = 0, border = 0, tint = [1, 1, 1], exposure = 1 }) {
  return `
precision highp float;
uniform sampler2D uMap;
uniform float uOpacity;
uniform float uFade;
uniform float uDissolve;
uniform float uReveal;
uniform float uTime;
uniform vec3 uTint;
uniform float uExposure;
uniform float uBorderGlow;
uniform vec2 uCover;
uniform vec2 uSize;
varying vec2 vUv;

float hash(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p){ vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
  return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y); }
float sdRound(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }

void main(){
  vec4 tex = texture2D(uMap, (vUv - 0.5) * uCover + 0.5);
  float alpha = tex.a;
  vec3 rgb = tex.rgb;

  ${rounded > 0 ? `
  vec2 p = (vUv - 0.5) * uSize;
  float d = sdRound(p, uSize * 0.5, ${rounded.toFixed(4)});
  float aa = 0.006;
  float inside = 1.0 - smoothstep(-aa, aa, d);
  alpha *= inside;
  float bw = ${Math.max(0.004, border).toFixed(4)};
  float ring = (1.0 - smoothstep(-aa, aa, d)) * smoothstep(-aa, aa, d + bw);
  rgb += vec3(0.72, 0.85, 0.42) * ring * uBorderGlow;
  ` : ``}

  float mask = 1.0;
  float edge = 0.0;
  if (uReveal < 0.999) {
    float n = vnoise(vUv * vec2(3.0, 4.6) + 2.7) * 0.72 + (1.0 - vUv.y) * 0.38;
    mask = smoothstep(uReveal - 0.16, uReveal + 0.16, n);
    edge = 1.0 - smoothstep(0.0, 0.07, abs(n - uReveal));
  }
  if (uDissolve < 0.999) {
    float n2 = vnoise(vUv * vec2(5.0, 3.4) + 8.1);
    mask *= smoothstep(uDissolve - 0.2, uDissolve + 0.2, n2 + vUv.x * 0.3);
  }

  rgb *= uTint * uExposure;
  rgb += vec3(0.65, 0.8, 0.34) * edge * 0.22;
  float outA = alpha * uOpacity * uFade * mask;
  if (outA < 0.003) discard;
  gl_FragColor = vec4(rgb, outA);
}`;
}

const DUST_VERT = `
uniform float uTime;
uniform float uSize;
uniform float uPixelRatio;
attribute float aScale;
attribute float aPhase;
varying float vAlpha;
void main(){
  vec3 p = position;
  p.y = mod(p.y + uTime * (0.045 + aPhase * 0.06) + 4.0, 8.0) - 4.0;
  p.x += sin(uTime * 0.21 + aPhase * 12.0) * 0.12;
  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  gl_Position = projectionMatrix * mv;
  float dist = -mv.z;
  gl_PointSize = uSize * aScale * uPixelRatio * (8.0 / max(dist, 0.5));
  vAlpha = smoothstep(1.0, 3.0, dist) * (1.0 - smoothstep(16.0, 26.0, dist)) * (0.35 + aPhase * 0.65);
}`;
const DUST_FRAG = `
precision highp float;
uniform float uOpacity;
varying float vAlpha;
void main(){
  vec2 p = gl_PointCoord - 0.5;
  float a = smoothstep(0.5, 0.06, length(p)) * vAlpha * uOpacity;
  gl_FragColor = vec4(vec3(0.82, 0.9, 0.67), a);
}`;

const SCAN_FRAG = `
precision highp float;
uniform sampler2D uMap;
uniform float uOpacity;
uniform float uFade;
uniform float uTime;
uniform float uReveal;
uniform float uScan;
varying vec2 vUv;
void main(){
  vec2 uv = vUv;
  vec3 tex = texture2D(uMap, uv).rgb;
  float l = dot(tex, vec3(0.2126, 0.7152, 0.0722));
  vec2 g = uv * vec2(26.0, 15.0);
  vec2 gl = abs(fract(g) - 0.5);
  float grid = smoothstep(0.49, 0.5, gl.x) * 0.05 + smoothstep(0.49, 0.5, gl.y) * 0.05;
  float sweep = exp(-pow((uv.y - uScan) * 26.0, 2.0));
  float line = smoothstep(0.006, 0.0, abs(uv.y - uScan));
  float border = smoothstep(0.014, 0.0, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
  vec3 col = vec3(0.72, 0.88, 0.45) * (grid + sweep * 0.26 + line * 0.5 + border * 0.45);
  col += vec3(0.8, 0.9, 0.6) * smoothstep(0.72, 1.0, l) * 0.06;
  gl_FragColor = vec4(col, uOpacity * uFade * smoothstep(0.0, 0.35, uReveal));
}`;

export async function createDeltaScene(canvas, { onProgress, onFallback } = {}) {
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: false, powerPreference: 'high-performance' });
  } catch (error) {
    onFallback?.('WebGL 初始化失败');
    return null;
  }
  if (!renderer.capabilities.isWebGL2) {
    onFallback?.('需要 WebGL2');
    return null;
  }
  renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
  renderer.setClearColor(0x070c0a, 1);
  const maxAniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(24, 1, 0.1, 120);
  camera.position.set(...CAMERA_KEYS.hero.a.pos);
  const camLook = new THREE.Vector3(...CAMERA_KEYS.hero.a.look);
  camera.lookAt(camLook);

  const rt = new THREE.WebGLRenderTarget(2, 2, { depthBuffer: true, type: THREE.UnsignedByteType });
  const postScene = new THREE.Scene();
  const postCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const postUniforms = {
    tDiffuse: { value: rt.texture },
    uRes: { value: new THREE.Vector2(2, 2) },
    uTime: { value: 0 },
    uEnter: { value: 0.0 },
    uVignette: { value: 0.72 },
    uGrain: { value: 0.035 },
    uChroma: { value: 0.0012 },
  };
  const postMesh = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), new THREE.ShaderMaterial({ uniforms: postUniforms, vertexShader: POST_VERT, fragmentShader: POST_FRAG }));
  postMesh.frustumCulled = false;
  postScene.add(postMesh);

  const loader = new THREE.TextureLoader();
  const texCache = new Map();
  let loaded = 0;
  const totalTextures = new Set();

  function loadTexture(url) {
    if (texCache.has(url)) return Promise.resolve(texCache.get(url));
    totalTextures.add(url);
    return loader.loadAsync(url).then((tex) => {
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.anisotropy = maxAniso;
      tex.minFilter = THREE.LinearMipmapLinearFilter;
      tex.magFilter = THREE.LinearFilter;
      tex.generateMipmaps = true;
      tex.needsUpdate = true;
      texCache.set(url, tex);
      loaded += 1;
      onProgress?.(loaded / Math.max(1, totalTextures.size));
      return tex;
    });
  }

  const groups = {};
  const planes = [];

  function planeMaterial(map, opts = {}) {
    const uniforms = {
      uMap: { value: map },
      uOpacity: { value: opts.opacity ?? 1 },
      uFade: { value: 1 },
      uDissolve: { value: 1 },
      uReveal: { value: 1 },
      uTime: { value: 0 },
      uTint: { value: new THREE.Color(...(opts.tint || [1, 1, 1])) },
      uExposure: { value: opts.exposure ?? 1 },
      uBorderGlow: { value: opts.borderGlow ?? 0 },
      uCover: { value: new THREE.Vector2(1, 1) },
      uSize: { value: new THREE.Vector2(1, 1) },
    };
    return new THREE.ShaderMaterial({ uniforms, vertexShader: PLANE_VERT, fragmentShader: planeFragment(opts), transparent: true, depthWrite: false, side: THREE.DoubleSide });
  }

  function addPlane(group, map, { width = 1, height = 1, position = [0, 0, 0], rotation = [0, 0, 0], ...opts } = {}) {
    const material = planeMaterial(map, opts);
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), material);
    mesh.position.set(...position);
    mesh.rotation.set(...rotation);
    const img = map?.image;
    const planeAspect = width / height;
    const texAspect = img ? img.width / img.height : 1;
    const cover = texAspect > planeAspect ? [planeAspect / texAspect, 1] : [1, texAspect / planeAspect];
    material.uniforms.uCover.value.set(cover[0], cover[1]);
    material.uniforms.uSize.value.set(width, height);
    mesh.userData.opts = opts;
    mesh.userData.baseOpacity = opts.opacity ?? 1;
    mesh.userData.basePosition = [...position];
    group.add(mesh);
    planes.push(mesh);
    return mesh;
  }

  function addShaderPlane(group, uniforms, fragmentShader, { width = 1, height = 1, position = [0, 0, 0] } = {}) {
    const material = new THREE.ShaderMaterial({ uniforms, vertexShader: PLANE_VERT, fragmentShader, transparent: true, depthWrite: false, side: THREE.DoubleSide });
    const mesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), material);
    mesh.position.set(...position);
    mesh.userData.isShader = true;
    group.add(mesh);
    return mesh;
  }

  function buildChapter(key) {
    const group = new THREE.Group();
    group.userData = { key, fade: 0, target: 0, reveal: 0, revealTarget: 0 };
    scene.add(group);
    groups[key] = group;
    return group;
  }

  function canvasTexture(draw, size = 256) {
    const c = document.createElement('canvas');
    c.width = size;
    c.height = size;
    draw(c.getContext('2d'), size);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }

  const glowTex = canvasTexture((ctx, s) => {
    const g = ctx.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    g.addColorStop(0, 'rgba(235,240,220,0.85)');
    g.addColorStop(0.4, 'rgba(200,220,170,0.16)');
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, s, s);
  });

  const urls = {
    operations: './assets/operations-scene.jpg',
    warfare: './assets/warfare-scene.jpg',
    spaceport: './assets/spaceport-scene.jpg',
    valley: './assets/longbow-valley-scene.jpg',
    operator: './assets/operation-role.webp',
    ayu: './assets/squad-ayu.webp',
    echo: './assets/squad-echo.webp',
    xiaoman: './assets/squad-xiaoman.webp',
    north: './assets/squad-north.webp',
    service: '/screens/service.png',
    ambientPoster: './assets/ambient-poster.jpg',
    heroBg: './assets/hero-bg.webp',
    heroOperator: './assets/hero-operator.webp',
    heroSupport: './assets/hero-support.webp',
    modeOpsBg: './assets/mode-operations-bg.webp',
    modeWarfBg: './assets/mode-warfare-bg.webp',
    modesOperator: './assets/modes-operator.webp',
    smoke: './assets/smoke-overlay.webp',
    terrainBg: './assets/terrain-bg.webp',
    terrainAlt: './assets/terrain-alt-bg.webp',
    squadBackdrop: './assets/squad-bg.webp',
    deployBg: './assets/deploy-bg.webp',
    deployOperator: './assets/deploy-operator.webp',
  };
  const t = {};
  for (const [key, url] of Object.entries(urls)) t[key] = await loadTexture(url);

  // 视频纹理（章节环境动效，进入后播放）
  function makeVideo(url, { loop = true } = {}) {
    const video = document.createElement('video');
    video.muted = true;
    video.loop = loop;
    video.playsInline = true;
    video.preload = 'none';
    video.src = url;
    let texture = null;
    function ensure() {
      if (texture) return texture;
      texture = new THREE.VideoTexture(video);
      texture.colorSpace = THREE.SRGBColorSpace;
      return texture;
    }
    return { video, ensure, get texture() { return texture; } };
  }
  const heroVideoSource = makeVideo('./assets/operations-ambient.mp4');
  const modesVideoSource = makeVideo('./assets/mode-anim.mp4');
  const deployVideoSource = makeVideo('./assets/universe-anim.mp4');
  let videoTexturesAttached = false;
  function attachVideoTextures() {
    if (videoTexturesAttached) return;
    videoTexturesAttached = true;
    heroVideo.material.uniforms.uMap.value = heroVideoSource.ensure();
    modesVideoPlane.material.uniforms.uMap.value = modesVideoSource.ensure();
    deployVideo.material.uniforms.uMap.value = deployVideoSource.ensure();
    for (const tex of [heroVideoSource.texture, modesVideoSource.texture, deployVideoSource.texture]) {
      if (tex) tex.needsUpdate = true;
    }
  }
  let lastVideoSignature = '';
  function syncVideos(force = false) {
    attachVideoTextures();
    const shouldPlay = state.entered > 0.5 && !state.reduced && !document.hidden;
    const pairs = [
      [heroVideoSource, state.active === 'hero'],
      [modesVideoSource, state.active === 'modes'],
      [deployVideoSource, state.active === 'deploy'],
    ];
    const signature = pairs.map(([, active]) => (active ? '1' : '0')).join('') + (shouldPlay ? '1' : '0');
    if (!force && signature === lastVideoSignature) return;
    lastVideoSignature = signature;
    for (const [source, active] of pairs) {
      if (active && shouldPlay) source.video.play?.().catch(() => {});
      else source.video.pause?.();
    }
  }

  // ── 首屏 ──
  const hero = buildChapter('hero');
  const heroBg = addPlane(hero, t.heroBg, { width: 13.5, height: 7.8, position: [0, 0, -5.8], opacity: 0.95, exposure: 0.9, tint: [1.02, 0.99, 0.93] });
  const heroVideo = addPlane(hero, t.ambientPoster, { width: 22, height: 13, position: [0, 0, -5.5], opacity: 0.2, exposure: 0.72, tint: [1.0, 0.97, 0.9] });
  const heroSmoke = addPlane(hero, t.smoke, { width: 20, height: 12, position: [0, -0.6, -3.4], opacity: 0.16, exposure: 1, tint: [0.9, 0.95, 0.86] });
  addPlane(hero, glowTex, { width: 7.5, height: 7.5, position: [1.5, -0.4, 0.4], opacity: 0.18, exposure: 1, tint: [0.9, 1.0, 0.8] });
  const heroSupport = addPlane(hero, t.heroSupport, { width: 2.7, height: 4.0, position: [-2.7, -1.0, 0.05], opacity: 0.5, exposure: 0.78, tint: [0.94, 0.97, 0.9] });
  heroSupport.userData.revealLocked = true;
  const heroOperator = addPlane(hero, t.heroOperator, { width: 4.4, height: 3.4, position: [1.45, -0.7, 1.2], opacity: 1, exposure: 0.98, tint: [1.02, 0.99, 0.95] });
  heroOperator.userData.revealLocked = true;

  // ── 行动方式 ──
  const modes = buildChapter('modes');
  const modesBgA = addPlane(modes, t.modeOpsBg, { width: 13, height: 7.6, position: [0, 0, -4.4], opacity: 0.96, exposure: 0.92, tint: [1, 0.99, 0.94] });
  const modesBgB = addPlane(modes, t.modeWarfBg, { width: 13, height: 7.6, position: [0, 0, -4.35], opacity: 0, exposure: 0.92, tint: [1, 0.99, 0.94] });
  const modesOperator = addPlane(modes, t.modesOperator, { width: 3.1, height: 3.8, position: [2.45, -0.9, 0.9], opacity: 0.62, exposure: 0.88, tint: [0.98, 0.98, 0.92] });
  const modesVideoPlane = addPlane(modes, t.modeOpsBg, { width: 20, height: 11.6, position: [0, 0, -4.1], opacity: 0.13, exposure: 0.8, tint: [1, 0.98, 0.92] });
  addPlane(modes, glowTex, { width: 9, height: 9, position: [1.6, 0.4, 0.6], opacity: 0.1, exposure: 1, tint: [0.8, 1, 0.8] });

  // ── 地形情报 ──
  const terrain = buildChapter('terrain');
  addPlane(terrain, t.terrainBg, { width: 14, height: 8.2, position: [0, 0, -6.2], opacity: 0.96, exposure: 1.0, tint: [0.97, 1, 0.99] });
  const mapGroup = new THREE.Group();
  mapGroup.rotation.x = -0.6;
  terrain.add(mapGroup);
  const mapActive = addPlane(mapGroup, t.spaceport, { width: 10.6, height: 6.1, opacity: 0.98, exposure: 1.0, tint: [0.98, 1.0, 0.97] });
  const mapAlt = addPlane(mapGroup, t.valley, { width: 10.6, height: 6.1, position: [0, 0, 0.02], opacity: 0, exposure: 1.0, tint: [0.98, 1.0, 0.97] });
  const scanUniforms = { uMap: { value: t.spaceport }, uOpacity: { value: 0.9 }, uFade: { value: 1 }, uTime: { value: 0 }, uReveal: { value: 1 }, uScan: { value: 0.3 } };
  const scanMesh = addShaderPlane(mapGroup, scanUniforms, SCAN_FRAG, { width: 10.6, height: 6.1, position: [0, 0, 0.06] });

  // ── 小队集结 ──
  const squad = buildChapter('squad');
  addPlane(squad, t.squadBackdrop, { width: 13.5, height: 7.9, position: [0, 0, -3.6], opacity: 0.3, exposure: 0.72, tint: [0.94, 0.98, 0.92] });
  const memberTextures = [t.ayu, t.echo, t.xiaoman, t.north];
  const memberMeshes = memberTextures.map((tex, i) => {
    const x = -1.9 + i * 1.27;
    const mesh = addPlane(squad, tex, {
      width: 0.92, height: 1.16,
      position: [x, i % 2 === 0 ? 0.16 : -0.04, 0.2 + (i % 2) * 0.22],
      rotation: [0, -x * 0.1, 0],
      opacity: 0.98, exposure: 1.0, tint: [1, 0.99, 0.96],
      rounded: 0.055, border: 0.012, borderGlow: 0.75,
    });
    mesh.userData.memberIndex = i;
    return mesh;
  });
  addPlane(squad, glowTex, { width: 9.5, height: 9.5, position: [0, -0.6, -1.8], opacity: 0.14, exposure: 1, tint: [0.9, 1, 0.82] });

  // ── 部署 ──
  const deploy = buildChapter('deploy');
  addPlane(deploy, t.deployBg, { width: 14, height: 8.2, position: [0, 0, -5.5], opacity: 0.92, exposure: 0.88, tint: [1, 0.98, 0.92] });
  const deployVideo = addPlane(deploy, t.deployBg, { width: 18, height: 10.5, position: [0, 0, -5.3], opacity: 0.14, exposure: 0.8, tint: [1, 0.97, 0.9] });
  addPlane(deploy, t.deployOperator, { width: 3.2, height: 3.9, position: [-2.5, -1.0, 0.2], opacity: 0.5, exposure: 0.8, tint: [0.95, 0.98, 0.92] });
  addPlane(deploy, glowTex, { width: 6.6, height: 6.6, position: [1.35, -0.2, 0.4], opacity: 0.2, exposure: 1, tint: [0.85, 1, 0.8] });
  const deployPhone = addPlane(deploy, t.service, { width: 1.28, height: 2.77, position: [1.5, -0.15, 0.9], rotation: [0, -0.22, 0], opacity: 1, exposure: 0.98, rounded: 0.1, border: 0.008, borderGlow: 0.8 });

  // ── 尘粒 ──
  function dustPoints(count, spread, zMin, zMax, size) {
    const positions = new Float32Array(count * 3);
    const scales = new Float32Array(count);
    const phases = new Float32Array(count);
    for (let i = 0; i < count; i++) {
      positions[i * 3] = (Math.random() - 0.5) * spread;
      positions[i * 3 + 1] = (Math.random() - 0.5) * spread * 0.9;
      positions[i * 3 + 2] = lerp(zMin, zMax, Math.random());
      scales[i] = 0.5 + Math.random() * 1.6;
      phases[i] = Math.random();
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    geometry.setAttribute('aScale', new THREE.BufferAttribute(scales, 1));
    geometry.setAttribute('aPhase', new THREE.BufferAttribute(phases, 1));
    const material = new THREE.ShaderMaterial({
      uniforms: { uTime: { value: 0 }, uSize: { value: size }, uPixelRatio: { value: 1 }, uOpacity: { value: 0.9 } },
      vertexShader: DUST_VERT,
      fragmentShader: DUST_FRAG,
      transparent: true,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    const points = new THREE.Points(geometry, material);
    points.frustumCulled = false;
    scene.add(points);
    return points;
  }
  const dust = dustPoints(380, 16, -2, 4.5, 2.4);

  const state = {
    entered: 0,
    enteredTarget: 0,
    reduced: false,
    time: 0,
    pointer: new THREE.Vector2(0, 0),
    pointerTarget: new THREE.Vector2(0, 0),
    active: 'hero',
    progress: { hero: 0, modes: 0, terrain: 0, squad: 0, deploy: 0 },
    mode: 'operations',
    map: 'spaceport',
    hold: 0,
    holdTarget: 0,
    ready: false,
    dpr: 1,
    rawMode: false,
    squadHover: -1,
    mapDrag: 0,
    mapDragTarget: 0,
    scanPulseT: 0,
  };
  const groupKeys = ['hero', 'modes', 'terrain', 'squad', 'deploy'];
  for (const key of groupKeys) {
    groups[key].userData.revealTarget = key === 'hero' ? 1 : 0;
    groups[key].userData.reveal = key === 'hero' ? 0 : 0;
  }

  const camPos = camera.position.clone();
  const camLookCurrent = camLook.clone();
  const camTarget = { pos: new THREE.Vector3(), look: new THREE.Vector3() };
  const raycaster = new THREE.Raycaster();
  const pointerNdc = new THREE.Vector2(0, 0);

  function cameraTargetFor(key, progress) {
    const portrait = camera.aspect < 0.82;
    const cfg = CAMERA_KEYS[key] || CAMERA_KEYS.hero;
    const p = state.entered < 0.5 ? 0 : clamp(progress, 0, 1);
    camTarget.pos.set(lerp(cfg.a.pos[0], cfg.b.pos[0], p), lerp(cfg.a.pos[1], cfg.b.pos[1], p), lerp(cfg.a.pos[2], cfg.b.pos[2], p));
    camTarget.look.set(lerp(cfg.a.look[0], cfg.b.look[0], p), lerp(cfg.a.look[1], cfg.b.look[1], p), lerp(cfg.a.look[2], cfg.b.look[2], p));
    if (portrait) {
      if (key === 'hero') { camTarget.pos.set(0.1, 0.25, 11.4); camTarget.look.set(0, 0.05, -3.2); }
      if (key === 'modes') { camTarget.pos.set(0.2, 0.05, 10.2); camTarget.look.set(0, 0, -4.3); }
      if (key === 'terrain') { camTarget.pos.set(0.1, 3.2, 8.6); camTarget.look.set(0, -0.9, -2.2); }
      if (key === 'squad') { const pan = lerp(-1.4, 1.4, p); camTarget.pos.set(pan, 0.4, 7.4); camTarget.look.set(pan, 0.02, -0.3); }
      if (key === 'deploy') { camTarget.pos.set(0.3, 0.2, 10.4); camTarget.look.set(0, 0, -3.3); }
    }
    if (!state.reduced) {
      camTarget.pos.x += state.pointer.x * 0.16;
      camTarget.pos.y += -state.pointer.y * 0.1;
      camTarget.look.x += state.pointer.x * 0.06;
      camTarget.look.y += -state.pointer.y * 0.04;
    }
    if (state.active === 'squad') camTarget.look.x += state.pointer.x * 0.25;
    const intro = 1 - smoothstep(0, 1, state.entered);
    camTarget.pos.z += intro * (portrait ? 1.6 : 2.6);
    camTarget.pos.y += intro * 0.35;
  }

  function layoutForViewport() {
    const portrait = camera.aspect < 0.82;
    state.portrait = portrait;
    if (portrait) {
      heroBg.scale.set(1.16, 1.16, 1);
      heroOperator.position.set(0.35, -1.25, 1.2);
      heroOperator.scale.set(0.72, 0.72, 1);
      heroSupport.position.set(-1.5, -1.7, 0.1);
      deployPhone.position.set(0.85, -0.1, 0.9);
    } else {
      heroBg.scale.set(1, 1, 1);
      heroOperator.position.set(1.45, -0.7, 1.2);
      heroOperator.scale.set(1, 1, 1);
      heroSupport.position.set(-2.2, -0.9, 0.1);
      deployPhone.position.set(1.5, -0.15, 0.9);
    }
  }

  function resize() {
    const w = canvas.clientWidth || window.innerWidth;
    const h = canvas.clientHeight || window.innerHeight;
    const dpr = clamp(window.devicePixelRatio || 1, 1, window.innerWidth < 900 ? 1.3 : 1.7);
    state.dpr = dpr;
    renderer.setPixelRatio(dpr);
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.fov = w / h < 1 ? 34 : 24;
    camera.updateProjectionMatrix();
    const rw = Math.max(2, Math.floor(w * dpr * 0.9));
    const rh = Math.max(2, Math.floor(h * dpr * 0.9));
    rt.setSize(rw, rh);
    postUniforms.uRes.value.set(rw, rh);
    dust.material.uniforms.uPixelRatio.value = dpr;
    layoutForViewport();
  }

  function updateMaterials(dt) {
    for (const key of groupKeys) {
      const g = groups[key];
      const targetFade = key === state.active && state.entered > 0.15 ? 1 : 0;
      g.userData.fade = damp(g.userData.fade, targetFade, 2.6, dt);
      const revealTarget = key === state.active ? 1 : g.userData.revealTarget;
      g.userData.reveal = damp(g.userData.reveal, revealTarget, 2.4, dt);
      g.visible = g.userData.fade > 0.002 || g.userData.reveal < 0.999;
    }
    for (const mesh of planes) {
      const parent = mesh.parent;
      const g = parent?.userData?.key ? parent : parent?.parent?.userData?.key ? parent.parent : null;
      const fade = g ? g.userData.fade : 1;
      const reveal = g ? g.userData.reveal : 1;
      const u = mesh.material.uniforms;
      const revealValue = reveal > 0.985 ? 1 : reveal;
      u.uFade.value = fade > 0.985 ? 1 : fade;
      if (!mesh.userData.revealLocked) u.uReveal.value = revealValue;
      u.uTime.value = state.time;
    }
    const modeA = state.mode === 'operations' ? 1 : 0;
    modesBgA.material.uniforms.uOpacity.value = damp(modesBgA.material.uniforms.uOpacity.value, modeA * 0.96, 4.0, dt);
    modesBgB.material.uniforms.uOpacity.value = damp(modesBgB.material.uniforms.uOpacity.value, (1 - modeA) * 0.96, 4.0, dt);
    modesBgB.visible = modesBgB.material.uniforms.uOpacity.value > 0.01;
    const mapA = state.map === 'spaceport' ? 1 : 0;
    mapActive.material.uniforms.uOpacity.value = damp(mapActive.material.uniforms.uOpacity.value, mapA * 0.95, 4.0, dt);
    mapAlt.material.uniforms.uOpacity.value = damp(mapAlt.material.uniforms.uOpacity.value, (1 - mapA) * 0.95, 4.0, dt);
    scanUniforms.uMap.value = state.map === 'spaceport' ? t.spaceport : t.valley;
    scanUniforms.uFade.value = groups.terrain.userData.fade > 0.985 ? 1 : groups.terrain.userData.fade;
    scanUniforms.uReveal.value = groups.terrain.userData.reveal > 0.985 ? 1 : groups.terrain.userData.reveal;
    scanMesh.visible = groups.terrain.userData.fade > 0.003;
    scanMesh.visible = groups.terrain.userData.fade > 0.003 && state.active === 'terrain';
    mapGroup.rotation.z = damp(mapGroup.rotation.z, state.mapDragTarget * 0.14, 2.2, dt);
    mapGroup.rotation.x = damp(mapGroup.rotation.x, -0.6 + state.mapDragTarget * 0.1, 2.2, dt);
    if (state.scanPulseT > 0) {
      state.scanPulseT = Math.max(0, state.scanPulseT - dt);
      const k = 1 - state.scanPulseT / 1.6;
      scanUniforms.uScan.value = 0.95 - k * 0.82;
    } else {
      scanUniforms.uScan.value = 0.16 + state.progress.terrain * 0.68;
    }
    const enterReveal = smoothstep(0.02, 1, state.entered);
    heroOperator.material.uniforms.uReveal.value = enterReveal;
    heroSupport.material.uniforms.uReveal.value = enterReveal;
    heroBg.material.uniforms.uExposure.value = 0.9 + state.hold * 0.06;
    const opTargetX = state.portrait ? 0.35 : 1.45;
    heroOperator.position.x = damp(heroOperator.position.x, opTargetX - state.hold * 0.08, 2.0, dt);
    modesOperator.position.x = damp(modesOperator.position.x, (state.portrait ? 0.6 : 2.45) + state.pointer.x * 0.12, 2.4, dt);
    modesOperator.position.y = damp(modesOperator.position.y, (state.portrait ? -1.5 : -0.9) + state.pointer.y * 0.06, 2.4, dt);
    memberMeshes.forEach((mesh, i) => {
      mesh.userData.hover = damp(mesh.userData.hover ?? 0, state.squadHover === i ? 1 : 0, 6.0, dt);
      const s = 1 + mesh.userData.hover * 0.07;
      mesh.scale.set(s, s, 1);
      mesh.material.uniforms.uBorderGlow.value = 0.35 + mesh.userData.hover * 1.2;
      mesh.material.uniforms.uExposure.value = 0.95 + mesh.userData.hover * 0.12;
      mesh.position.z = damp(mesh.position.z, mesh.userData.basePosition[2] + mesh.userData.hover * 0.26, 5.0, dt);
    });
    deployPhone.rotation.y = damp(deployPhone.rotation.y, -0.22 + state.pointer.x * 0.1, 3.0, dt);
    deployPhone.rotation.x = damp(deployPhone.rotation.x, -state.pointer.y * 0.06, 3.0, dt);
    dust.material.uniforms.uTime.value = state.time;
    const dustTarget = state.active === 'modes' ? 0.4 : state.active === 'terrain' ? 0.35 : 0.9;
    dust.material.uniforms.uOpacity.value = damp(dust.material.uniforms.uOpacity.value, dustTarget, 2.0, dt);
  }

  function render(dt) {
    state.time += state.reduced ? 0 : dt;
    state.pointer.x = damp(state.pointer.x, state.pointerTarget.x, 3.4, dt);
    state.pointer.y = damp(state.pointer.y, state.pointerTarget.y, 3.4, dt);
    state.entered = damp(state.entered, state.enteredTarget, 1.4, dt);
    state.hold = damp(state.hold, state.holdTarget, 2.4, dt);
    const key = state.active;
    cameraTargetFor(key, state.progress[key] || 0);
    scanMesh.visible = key === 'terrain' && state.entered > 0.2;
    camPos.x = damp(camPos.x, camTarget.pos.x, 2.2, dt);
    camPos.y = damp(camPos.y, camTarget.pos.y, 2.2, dt);
    camPos.z = damp(camPos.z, camTarget.pos.z, 2.2, dt);
    camLookCurrent.x = damp(camLookCurrent.x, camTarget.look.x, 2.4, dt);
    camLookCurrent.y = damp(camLookCurrent.y, camTarget.look.y, 2.4, dt);
    camLookCurrent.z = damp(camLookCurrent.z, camTarget.look.z, 2.4, dt);
    camera.position.copy(camPos);
    camera.lookAt(camLookCurrent);
    syncVideos();
    updateMaterials(dt);
    postUniforms.uTime.value = state.time;
    postUniforms.uEnter.value = damp(postUniforms.uEnter.value, state.entered, 2.2, dt);
    if (state.rawMode) {
      renderer.setRenderTarget(null);
      renderer.clear();
      renderer.render(scene, camera);
    } else {
      renderer.setRenderTarget(rt);
      renderer.clear();
      renderer.render(scene, camera);
      renderer.setRenderTarget(null);
      renderer.render(postScene, postCamera);
    }
  }

  function setActive(key) {
    if (!groups[key] || state.active === key) return;
    state.active = key;
    for (const k of groupKeys) if (k !== key) groups[k].userData.revealTarget = 0;
    groups[key].userData.revealTarget = 1;
  }
  function setProgress(key, value) { if (state.progress[key] !== undefined) state.progress[key] = clamp(value, 0, 1); }
  function setEntered(v) {
    state.enteredTarget = v ? 1 : 0;
    state.ready = Boolean(v);
    if (v) syncVideos();
  }
  function setPointer(x, y) { state.pointerTarget.set(clamp(x, -1, 1), clamp(y, -1, 1)); }
  function setHold(v) { state.holdTarget = v ? 1 : 0; }
  function setMode(mode) { state.mode = mode === 'warfare' ? 'warfare' : 'operations'; }
  function setMap(map) { state.map = map === 'valley' ? 'valley' : 'spaceport'; }
  function setReduced(v) {
    state.reduced = Boolean(v);
    if (state.reduced) {
      heroVideoSource.video.pause?.();
      modesVideoSource.video.pause?.();
      deployVideoSource.video.pause?.();
    } else {
      syncVideos();
    }
  }
  function setPointerNdc(nx, ny) { pointerNdc.set(nx, ny); }
  function pick() {
    raycaster.setFromCamera(pointerNdc, camera);
    const targets = state.active === 'squad' ? memberMeshes : state.active === 'deploy' ? [deployPhone] : [];
    const hits = raycaster.intersectObjects(targets, false);
    if (!hits.length) return null;
    const mesh = hits[0].object;
    if (mesh.userData.memberIndex !== undefined) return { type: 'member', index: mesh.userData.memberIndex };
    if (mesh === deployPhone) return { type: 'deploy' };
    return null;
  }
  function setHover(result) { state.squadHover = result?.type === 'member' ? result.index : -1; }
  function setMapDrag(delta) { state.mapDragTarget = clamp(delta, -1, 1); }
  function scanPulse() { state.scanPulseT = 1.6; }
  function startVideo() { syncVideos(); }
  function stopVideo() {
    heroVideoSource.video.pause?.();
    modesVideoSource.video.pause?.();
    deployVideoSource.video.pause?.();
  }

  resize();
  window.addEventListener('resize', resize);

  let last = 0;
  let raf = 0;
  function loop(now) {
    raf = requestAnimationFrame(loop);
    const dt = last ? Math.min(0.05, (now - last) / 1000) : 0.016;
    last = now;
    if (document.hidden) return;
    render(state.reduced ? 0.016 : dt);
  }
  requestAnimationFrame(loop);

  return {
    setActive,
    setProgress,
    setEntered,
    setPointer,
    setHold,
    setMode,
    setMap,
    setReduced,
    setPointerNdc,
    pick,
    setHover,
    setMapDrag,
    scanPulse,
    setRawMode: (v) => { state.rawMode = Boolean(v); },
    startVideo,
    stopVideo,
    resize,
    get ready() { return state.ready; },
    captureRT() {
      render(0.016);
      const w = rt.width, h = rt.height;
      const buf = new Uint8Array(w * h * 4);
      renderer.readRenderTargetPixels(rt, 0, 0, w, h, buf);
      const c = document.createElement('canvas');
      c.width = w; c.height = h;
      const ctx = c.getContext('2d');
      const img = ctx.createImageData(w, h);
      for (let y = 0; y < h; y++) {
        for (let x = 0; x < w; x++) {
          const src = ((h - 1 - y) * w + x) * 4;
          const dst = (y * w + x) * 4;
          img.data[dst] = Math.min(255, Math.pow(buf[src] / 255, 1 / 2.2) * 255);
          img.data[dst + 1] = Math.min(255, Math.pow(buf[src + 1] / 255, 1 / 2.2) * 255);
          img.data[dst + 2] = Math.min(255, Math.pow(buf[src + 2] / 255, 1 / 2.2) * 255);
          img.data[dst + 3] = 255;
        }
      }
      ctx.putImageData(img, 0, 0);
      return c.toDataURL('image/png');
    },
    dumpPlanes() {
      return planes.map((mesh) => {
        const parent = mesh.parent;
        const g = parent?.userData?.key ? parent : parent?.parent?.userData?.key ? parent.parent : null;
        const u = mesh.material.uniforms || {};
        return {
          key: g?.userData?.key ?? '?', z: +mesh.position.z.toFixed(2),
          fade: u.uFade ? +u.uFade.value.toFixed(3) : null,
          opacity: u.uOpacity ? +u.uOpacity.value.toFixed(3) : null,
          reveal: u.uReveal ? +u.uReveal.value.toFixed(3) : null,
          visible: mesh.visible, kind: u.uMap?.value?.isVideoTexture ? 'video' : (mesh.material.fragmentShader.includes('sdRound') ? 'rounded' : 'image'),
        };
      });
    },
    setGroupsVisible(keys) {
      for (const k of groupKeys) groups[k].visible = keys.includes(k);
    },
    projectGroup(key) {
      camera.updateMatrixWorld(true);
      const group = groups[key];
      const out = [];
      group.traverse((c) => {
        if (!c.isMesh) return;
        const geo = c.geometry;
        const pos = geo.attributes.position;
        const corners = [];
        for (const i of [0, 1, 2, 3]) {
          const v = new THREE.Vector3().fromBufferAttribute(pos, i).applyMatrix4(c.matrixWorld).project(camera);
          corners.push([+v.x.toFixed(2), +v.y.toFixed(2)]);
        }
        out.push({ type: c.type, visible: c.visible, corners });
      });
      return out;
    },
    inspect() {
      camera.updateMatrixWorld(true);
      const frustum = new THREE.Frustum().setFromProjectionMatrix(new THREE.Matrix4().multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse));
      return {
        camera: { pos: camera.position.toArray().map(v => +v.toFixed(2)), fov: camera.fov, aspect: +camera.aspect.toFixed(3), quat: camera.quaternion.toArray().map(v => +v.toFixed(2)) },
        groups: groupKeys.map(k => ({
          key: k,
          visible: groups[k].visible,
          children: groups[k].children.map(c => {
            const wp = new THREE.Vector3(); c.getWorldPosition(wp);
            const u = c.material?.uniforms || {};
            return { pos: wp.toArray().map(v => +v.toFixed(2)), scale: c.scale.toArray().map(v => +v.toFixed(2)), visible: c.visible, inFrustum: frustum.containsPoint(wp), fade: u.uFade?.value !== undefined ? +u.uFade.value.toFixed(3) : null, reveal: u.uReveal?.value !== undefined ? +u.uReveal.value.toFixed(3) : null, opacity: u.uOpacity?.value !== undefined ? +u.uOpacity.value.toFixed(3) : null };
          })
        }))
      };
    },
    probe() {
      render(0.016);
      const buf = new Uint8Array(4);
      renderer.readRenderTargetPixels(rt, Math.floor(rt.width / 2), Math.floor(rt.height / 2), 1, 1, buf);
      const near = new Uint8Array(4);
      renderer.readRenderTargetPixels(rt, Math.floor(rt.width * 0.25), Math.floor(rt.height * 0.3), 1, 1, near);
      return { center: Array.from(buf), quarter: Array.from(near), draws: renderer.info.render.calls, triangles: renderer.info.render.triangles, camera: camPos.toArray().map(v => Number(v.toFixed(2))) };
    },
    get debug() { return { active: state.active, entered: state.entered, progress: { ...state.progress }, groups: groupKeys.map(k => ({ key: k, fade: Number(groups[k].userData.fade.toFixed(3)), reveal: Number(groups[k].userData.reveal.toFixed(3)), visible: groups[k].visible })) }; },
    destroy() {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', resize);
      renderer.dispose();
    },
  };
}
