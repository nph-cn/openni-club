import {createReadStream} from 'node:fs';
import {realpath, stat} from 'node:fs/promises';
import {createServer} from 'node:http';
import {extname, isAbsolute, relative, resolve, sep} from 'node:path';
import {pipeline} from 'node:stream/promises';

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.mp3': 'audio/mpeg',
  '.ogg': 'audio/ogg',
  '.wasm': 'application/wasm',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
};

function isWithin(root, path) {
  const part = relative(root, path);
  return part === '' || (part !== '..' && !part.startsWith(`..${sep}`) && !isAbsolute(part));
}

function fail(status) {
  return Object.assign(new Error('预览请求不可用'), {status});
}

async function findFile(root, rawUrl) {
  // 在 URL 规范化之前检查原始路径，防止父目录片段被提前消去。
  let pathname;
  try {
    pathname = decodeURIComponent((rawUrl || '/').split(/[?#]/, 1)[0]);
  } catch {
    throw fail(400);
  }
  if (!pathname.startsWith('/') || pathname.includes('\0')) throw fail(400);
  if (pathname.includes('\\') || pathname.split('/').includes('..')) throw fail(403);
  const base = await realpath(root);
  let path = resolve(base, `.${pathname}`);
  if (!isWithin(base, path)) throw fail(403);
  path = await realpath(path);
  if (!isWithin(base, path)) throw fail(403);
  if ((await stat(path)).isDirectory()) path = await realpath(resolve(path, 'index.html'));
  if (!isWithin(base, path)) throw fail(403);
  const info = await stat(path);
  if (!info.isFile()) throw fail(404);
  return {path, size: info.size};
}

function singleRange(value, size) {
  // 只支持单段字节范围；不支持的多段与非法范围统一返回 416。
  const match = /^bytes=(\d*)-(\d*)$/i.exec(value.trim());
  if (!match || (!match[1] && !match[2]) || size === 0) return null;
  const length = BigInt(size);
  if (!match[1]) {
    const suffix = BigInt(match[2]);
    if (suffix === 0n) return null;
    return {start: Number(suffix >= length ? 0n : length - suffix), end: size - 1};
  }
  const start = BigInt(match[1]);
  const requestedEnd = match[2] ? BigInt(match[2]) : length - 1n;
  if (start >= length || requestedEnd < start) return null;
  return {start: Number(start), end: Number(requestedEnd >= length ? length - 1n : requestedEnd)};
}

export function createPreviewServer({root}) {
  const directory = resolve(root);
  return createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    const sendError = (status, extra = {}) => {
      res.writeHead(status, {'Content-Length': '0', ...extra});
      res.end();
    };
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      sendError(405, {Allow: 'GET, HEAD'});
      return;
    }
    try {
      const file = await findFile(directory, req.url);
      const headers = {
        'Content-Type': types[extname(file.path).toLowerCase()] || 'application/octet-stream',
        'Content-Length': String(file.size),
        'Accept-Ranges': 'bytes',
      };
      let range;
      // Range 只适用于 GET；没有校验器时不满足 If-Range，返回完整表示。
      if (req.method === 'GET' && req.headers.range && !req.headers['if-range']) {
        range = singleRange(req.headers.range, file.size);
        if (!range) {
          sendError(416, {'Content-Range': `bytes */${file.size}`, 'Accept-Ranges': 'bytes'});
          return;
        }
        headers['Content-Length'] = String(range.end - range.start + 1);
        headers['Content-Range'] = `bytes ${range.start}-${range.end}/${file.size}`;
      }
      res.writeHead(range ? 206 : 200, headers);
      if (req.method === 'HEAD') {
        res.end();
        return;
      }
      await pipeline(createReadStream(file.path, range), res);
    } catch (error) {
      if (res.headersSent) {
        res.destroy(error);
        return;
      }
      const status = error.status || (['ENOENT', 'ENOTDIR'].includes(error.code) ? 404 : error.code === 'EACCES' ? 403 : 500);
      sendError(status);
    }
  });
}
