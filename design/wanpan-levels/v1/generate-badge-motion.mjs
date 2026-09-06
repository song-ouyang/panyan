/**
 * Wanpan Diary · level badge earned. One-shot, 512 × 512, 60 fps, 1.1 s.
 * Usage: node generate-badge-motion.mjs <badge.png> <official-player-root>
 * The source PNG is retained as a single illustrated image layer. Only its
 * transform/opacity, a supporting ring, and eight sparse accents animate.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const [inputArg, playerArg] = process.argv.slice(2);
if (!inputArg || !playerArg) {
  console.error('Usage: node generate-badge-motion.mjs <badge.png> <official-player-root>');
  process.exit(1);
}
const input = path.resolve(inputArg);
const player = path.resolve(playerArg);
if (!fs.existsSync(path.join(player, 'src/context/canvas.tsx'))) {
  throw new Error('Expected the official Text-to-Lottie player root.');
}
const png = fs.readFileSync(input);
if (png.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') {
  throw new Error('Expected a PNG source with transparent edges.');
}
const imageW = png.readUInt32BE(16);
const imageH = png.readUInt32BE(20);
const sourceHasAlpha = [4, 6].includes(png[25]);
const fr = 60;
const op = 66;
const constant = k => ({ a: 0, k });
const rgba = hex => [...hex.match(/\w\w/g).map(x => parseInt(x, 16) / 255), 1];
const curves = {
  entrance: [0.20, 0.75, 0.34, 0.94],
  settle: [0.00, 0.65, 0.51, 0.99],
  soft: [0.16, 0.48, 0.48, 1.00],
  fade: [0.32, 0, 0.67, 1],
};
const vector = v => Array.isArray(v) ? v : [v];
const animated = (frames, curve = 'settle') => ({
  a: 1,
  k: frames.map(([t, value, easing], i) => {
    const s = vector(value);
    if (i === frames.length - 1) return { t, s };
    const b = curves[easing || curve];
    return { t, s, e: vector(frames[i + 1][1]), o: { x: [b[0]], y: [b[1]] }, i: { x: [b[2]], y: [b[3]] } };
  }),
});
const identity = () => ({ o: constant(100), r: constant(0), p: constant([0, 0, 0]), a: constant([0, 0, 0]), s: constant([100, 100, 100]) });
let nextIndex = 1;
const layer = (nm, ty, extra = {}) => ({ ddd: 0, ind: nextIndex++, ty, nm, sr: 1, ks: identity(), ao: 0, ip: 0, op, st: 0, bm: 0, ...extra });
const fill = sid => ({ ty: 'fl', c: { sid }, o: constant(100), r: 1, bm: 0, nm: sid });
const disk = (size, sid) => [ { ty: 'el', p: constant([0, 0]), s: constant([size, size]), d: 1, nm: 'round accent' }, fill(sid) ];
const star = (size, sid) => {
  const vertices = [[0, -size], [size * 0.28, -size * 0.28], [size, 0], [size * 0.28, size * 0.28], [0, size], [-size * 0.28, size * 0.28], [-size, 0], [-size * 0.28, -size * 0.28]];
  return [{ ty: 'sh', ks: constant({ i: vertices.map(() => [0, 0]), o: vertices.map(() => [0, 0]), v: vertices, c: true }), nm: 'four-point accent' }, fill(sid)];
};

// A single focal element receives the only overshoot in the scene.
const baseScale = 448 / Math.max(imageW, imageH) * 100;
const size = factor => [baseScale * factor, baseScale * factor, 100];
const badge = layer('Earned badge · one restrained settle', 2, {
  refId: 'badge-main',
  ks: {
    o: animated([[0, 20], [7, 100], [65, 100]], 'entrance'),
    r: animated([[0, -10, 'entrance'], [34, 0], [65, 0]]),
    p: animated([[0, [256, 294, 0], 'entrance'], [27, [256, 256, 0]], [65, [256, 256, 0]]]),
    a: constant([imageW / 2, imageH / 2, 0]),
    s: animated([[0, size(0.68), 'entrance'], [27, size(1.06), 'soft'], [43, size(0.993), 'settle'], [54, size(1)], [65, size(1)]]),
  },
});
// The concept illustration currently has a cream matte. A native elliptical
// Lottie mask hides its square corners without modifying the source image.
// A future transparent image takes this same animation without the mask/matte.
if (!sourceHasAlpha) {
  const cx = imageW / 2;
  const cy = imageH / 2;
  const rx = imageW * 0.407;
  const ry = imageH * 0.407;
  const b = 0.5522847498;
  badge.hasMask = true;
  badge.masksProperties = [{
    inv: false, mode: 'a', nm: 'Concept matte · elliptical crop',
    pt: constant({
      v: [[cx, cy - ry], [cx + rx, cy], [cx, cy + ry], [cx - rx, cy]],
      i: [[-rx * b, 0], [0, -ry * b], [rx * b, 0], [0, ry * b]],
      o: [[rx * b, 0], [0, ry * b], [-rx * b, 0], [0, -ry * b]], c: true,
    }),
    o: constant(100), x: constant(0),
  }];
}

const accents = Array.from({ length: 8 }, (_, i) => {
  const angle = (i * 45 - 112) * Math.PI / 180;
  const start = 12 + i % 3 * 2;
  const end = 46 + i % 3 * 2;
  const at = radius => [256 + Math.cos(angle) * radius, 256 + Math.sin(angle) * radius, 0];
  return layer(`Sparse accent ${i + 1}`, 4, {
    ks: {
      o: animated([[0, 0], [start, 0], [start + 5, 85], [end - 9, 62], [end, 0], [65, 0]], 'fade'),
      r: constant(i * 18),
      p: animated([[0, at(136)], [start, at(136), 'soft'], [end, at(212 + i % 2 * 10)], [65, at(212 + i % 2 * 10)]]),
      a: constant([0, 0, 0]),
      s: constant([100, 100, 100]),
    },
    shapes: i % 3 === 0 ? star(8, i % 2 ? 'coral' : 'sunflower') : disk(i % 2 ? 8 : 6, i % 2 ? 'coral' : 'sunflower'),
  });
});
const ring = layer('Quiet celebration ring · behind the badge', 4, {
  ks: {
    o: animated([[0, 0], [10, 0], [20, 34], [43, 0], [65, 0]], 'fade'),
    r: constant(0), p: constant([256, 256, 0]), a: constant([0, 0, 0]),
    s: animated([[0, [70, 70, 100]], [10, [70, 70, 100], 'soft'], [43, [126, 126, 100]], [65, [126, 126, 100]]]),
  },
  shapes: [
    { ty: 'el', p: constant([0, 0]), s: constant([352, 352]), d: 1, nm: 'celebration ring' },
    { ty: 'st', c: { sid: 'coral' }, o: constant(100), w: { sid: 'ringWidth' }, lc: 2, lj: 2, ml: 4, bm: 0 },
  ],
});
const background = layer('Cream presentation background · concept preview only', 4, {
  shapes: [
    { ty: 'rc', p: constant([256, 256]), s: constant([512, 512]), r: constant(0) },
    fill('bgColor'),
  ],
});

const scene = {
  v: '5.12.2', fr, ip: 0, op, w: 512, h: 512,
  nm: 'Wanpan · Level badge earned · one shot', ddd: 0,
  assets: [{ id: 'badge-main', w: imageW, h: imageH, u: '', p: 'badge-main.png', e: 0 }],
  slots: {
    coral: { p: constant(rgba('FF6B52')) },
    sunflower: { p: constant(rgba('FFC943')) },
    ringWidth: { p: constant(2.5) },
    ...(!sourceHasAlpha ? { bgColor: { p: constant(rgba('FFF7E9')) } } : {}),
  },
  layers: [badge, ...accents, ring, ...(!sourceHasAlpha ? [background] : [])],
  markers: [
    { tm: 0, cm: 'acknowledge', dr: 7 },
    { tm: 27, cm: 'badge peak', dr: 1 },
    { tm: 54, cm: 'stable result; reduced motion uses this pose', dr: 12 },
  ],
};
const controls = { controls: [
  { sid: 'coral', label: '珊瑚色 / Coral' },
  { sid: 'sunflower', label: '向日葵色 / Sunflower' },
  { sid: 'ringWidth', label: '庆祝圆环线宽', min: 1, max: 4, step: 0.5 },
  ...(!sourceHasAlpha ? [{ sid: 'bgColor', label: '概念演示背景 / Cream' }] : []),
] };
const motionDir = path.join(here, 'motion');
const officialDir = path.join(player, 'public/projects/wanpan-levels/scene-1');
for (const dir of [motionDir, officialDir]) {
  fs.mkdirSync(dir, { recursive: true });
  const target = path.join(dir, 'lottie.json');
  // Re-read before replacement: the official UI can persist slot changes.
  if (fs.existsSync(target)) JSON.parse(fs.readFileSync(target, 'utf8'));
  fs.writeFileSync(target, JSON.stringify(scene));
  fs.writeFileSync(path.join(dir, 'controls.json'), `${JSON.stringify(controls, null, 2)}\n`);
  fs.writeFileSync(path.join(dir, 'badge-main.png'), png);
}
const embedded = structuredClone(scene);
embedded.assets[0].p = `data:image/png;base64,${png.toString('base64')}`;
embedded.assets[0].e = 1;
const embeddedJson = JSON.stringify(embedded);
if (Buffer.byteLength(embeddedJson) <= 1024 * 1024) {
  fs.writeFileSync(path.join(motionDir, 'badge-earned.embedded.json'), embeddedJson);
}
fs.writeFileSync(path.join(motionDir, 'motion-spec.json'), `${JSON.stringify({
  size: [512, 512], fps: fr, frames: op, durationSeconds: op / fr, loop: false,
  transparent: sourceHasAlpha, embeddedText: false, stableFrame: 54, reducedMotionFrame: 65,
  assetStatus: sourceHasAlpha ? 'transparent raster artwork' : 'concept cream-matte raster; native elliptical mask; needs transparent or layered vector art for production integration',
  mainImage: 'badge-main.png', imageSize: [imageW, imageH],
  officialRoute: '/wanpan-levels/scene-1',
  beats: [
    { seconds: 0, description: '徽章以 0.68 倍、-10 度、低位开始出现' },
    { seconds: 0.1167, description: '主图完全显现；结果可立即读到' },
    { seconds: 0.45, description: '1.06 倍轻量峰值，稀疏圆点和星屑陪衬' },
    { seconds: 0.9, description: '主图稳定，圆环与粒子已经全部消失' },
    { seconds: 1.1, description: '播放结束；产品保持结果直到明确关闭' },
  ],
}, null, 2)}\n`);
console.log(JSON.stringify({ officialDir, motionDir, imageW, imageH, jsonBytes: Buffer.byteLength(JSON.stringify(scene)), embedded: Buffer.byteLength(embeddedJson) <= 1024 * 1024 }, null, 2));
