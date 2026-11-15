import assert from 'node:assert/strict';
import {mkdtemp, mkdir, rm, symlink, writeFile} from 'node:fs/promises';
import {request} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, before, describe, it} from 'node:test';
import {createPreviewServer} from '../lib/preview-server.mjs';

describe('本地预览资源服务', () => {
  let temporary, server, port;
  const movie = Buffer.from(Array.from({length: 2048}, (_, i) => i % 256));
  const get = (path, {method = 'GET', headers = {}} = {}) => new Promise((resolve, reject) => {
    const req = request({host: '127.0.0.1', port, path, method, headers}, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve({status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks)}));
      res.on('error', reject);
    });
    req.on('error', reject);
    req.end();
  });

  before(async () => {
    temporary = await mkdtemp(join(tmpdir(), 'openni-preview-test-'));
    const root = join(temporary, 'public');
    await mkdir(join(root, 'nested'), {recursive: true});
    await mkdir(join(temporary, 'outside'));
    await Promise.all([
      writeFile(join(root, 'index.html'), '<h1>OpenNI</h1>'),
      writeFile(join(root, 'nested', 'index.html'), '<p>内页</p>'),
      writeFile(join(root, 'movie.mp4'), movie),
      writeFile(join(root, 'empty.mp4'), ''),
      writeFile(join(root, 'image.webp'), 'webp'),
      writeFile(join(root, 'font.ttf'), 'font'),
      writeFile(join(root, 'unknown.bin'), 'binary'),
      writeFile(join(temporary, 'outside', 'private.txt'), '不得暴露的测试数据'),
    ]);
    await symlink(join(temporary, 'outside'), join(root, 'escape'), process.platform === 'win32' ? 'junction' : 'dir');
    server = createPreviewServer({root});
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    port = server.address().port;
  });

  after(async () => {
    if (server) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    if (temporary) await rm(temporary, {recursive: true, force: true});
  });

  it('完整 MP4 响应逐字节一致，并提供类型、长度及范围声明', async () => {
    const res = await get('/movie.mp4?version=1');
    assert.equal(res.status, 200);
    assert.equal(res.headers['content-type'], 'video/mp4');
    assert.equal(res.headers['content-length'], String(movie.length));
    assert.equal(res.headers['accept-ranges'], 'bytes');
    assert.equal(res.headers['x-content-type-options'], 'nosniff');
    assert.deepEqual(res.body, movie);
  });

  it('单段、开放末尾、超长末尾均返回正确 206 字节段', async () => {
    for (const [value, start, end] of [['bytes=7-39', 7, 39], ['bytes=2030-', 2030, 2047], ['bytes=2030-999999999999999999999', 2030, 2047]]) {
      const res = await get('/movie.mp4', {headers: {Range: value}});
      assert.equal(res.status, 206);
      assert.equal(res.headers['content-range'], `bytes ${start}-${end}/2048`);
      assert.equal(res.headers['content-length'], String(end - start + 1));
      assert.deepEqual(res.body, movie.subarray(start, end + 1));
    }
  });

  it('后缀范围与超过整片的后缀返回准确内容', async () => {
    for (const [value, start] of [['bytes=-19', 2029], ['bytes=-999999999999999999999', 0]]) {
      const res = await get('/movie.mp4', {headers: {Range: value}});
      assert.equal(res.status, 206);
      assert.equal(res.headers['content-range'], `bytes ${start}-2047/2048`);
      assert.deepEqual(res.body, movie.subarray(start));
    }
  });

  it('非法、越界、空后缀及未支持多段统一返回 416', async () => {
    for (const value of ['bytes=2048-', 'bytes=999999999999999999999-', 'bytes=9-3', 'bytes=-0', 'bytes=-', 'bytes=abc-def', 'bytes=0-2,4-6', 'items=0-2']) {
      const res = await get('/movie.mp4', {headers: {Range: value}});
      assert.equal(res.status, 416, value);
      assert.equal(res.headers['content-range'], 'bytes */2048');
      assert.equal(res.body.length, 0);
    }
    const empty = await get('/empty.mp4', {headers: {Range: 'bytes=0-'}});
    assert.equal(empty.status, 416);
    assert.equal(empty.headers['content-range'], 'bytes */0');
  });

  it('HEAD 返回完整资源头且没有响应体，忽略 Range', async () => {
    for (const headers of [{}, {Range: 'bytes=1-8'}]) {
      const res = await get('/movie.mp4', {method: 'HEAD', headers});
      assert.equal(res.status, 200);
      assert.equal(res.headers['content-type'], 'video/mp4');
      assert.equal(res.headers['content-length'], '2048');
      assert.equal(res.headers['content-range'], undefined);
      assert.equal(res.body.length, 0);
    }
  });

  it('不能校验 If-Range 时返回完整表示', async () => {
    const res = await get('/movie.mp4', {headers: {Range: 'bytes=0-5', 'If-Range': '"old-version"'}});
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, movie);
  });

  it('WebP、TTF 与目录首页保持正确类型和内容', async () => {
    for (const [path, type] of [['/image.webp', 'image/webp'], ['/font.ttf', 'font/ttf'], ['/unknown.bin', 'application/octet-stream'], ['/', 'text/html; charset=utf-8'], ['/nested/', 'text/html; charset=utf-8']]) {
      const res = await get(path);
      assert.equal(res.status, 200);
      assert.equal(res.headers['content-type'], type);
      assert.ok(res.body.length > 0);
    }
    assert.equal((await get('/nested/')).body.toString(), '<p>内页</p>');
  });

  it('拒绝原始、编码和 Windows 反斜杠父目录穿越', async () => {
    for (const path of ['/../outside/private.txt', '/%2e%2e/outside/private.txt', '/%2e%2e%2foutside/private.txt', '/..%5coutside%5cprivate.txt']) {
      const res = await get(path);
      assert.equal(res.status, 403, path);
      assert.equal(res.body.length, 0);
    }
  });

  it('目录符号链接不能越过发布根目录', async () => {
    const res = await get('/escape/private.txt');
    assert.equal(res.status, 403);
    assert.equal(res.body.length, 0);
  });

  it('坏编码、缺失文件和非读取方法返回明确错误且不泄漏文件', async () => {
    assert.equal((await get('/%ZZ')).status, 400);
    assert.equal((await get('/%00')).status, 400);
    const missing = await get('/missing.mp4', {method: 'HEAD'});
    assert.equal(missing.status, 404);
    assert.equal(missing.body.length, 0);
    const post = await get('/movie.mp4', {method: 'POST'});
    assert.equal(post.status, 405);
    assert.equal(post.headers.allow, 'GET, HEAD');
    assert.equal(post.body.length, 0);
  });
});
