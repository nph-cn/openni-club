// 一次性素材准备：把 App 演示成员头像转成专题用的小尺寸 webp。
// 运行：node work/openni-club/scripts/prepare-delta-assets.mjs
// 输出写入 apps/showcase/delta/assets/，随后随 showcase 一起构建。
import sharp from 'sharp';
import { mkdir } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = resolve(process.cwd());
const srcDir = resolve(root, 'apps/mobile/assets/demo');
const outDir = resolve(root, 'apps/showcase/delta/assets');
await mkdir(outDir, { recursive: true });

const members = [
  ['p1', 'player-yu.png', 'squad-ayu.webp'],
  ['p2', 'player-bei.png', 'squad-echo.webp'],
  ['p3', 'player-xiaoman.webp', 'squad-xiaoman.webp'],
  ['p4', 'player-north.webp', 'squad-north.webp'],
];

for (const [id, source, target] of members) {
  await sharp(resolve(srcDir, source))
    .resize(512, 512, { fit: 'cover', position: 'top' })
    .webp({ quality: 82 })
    .toFile(resolve(outDir, target));
  console.log(id, source, '->', target);
}
