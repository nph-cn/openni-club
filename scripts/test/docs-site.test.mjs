import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve,dirname,basename} from 'node:path';
import {buildDocs} from '../lib/docs-site.mjs';

test('文档的QA、源码与页底来源使用预览分支，站内文档和默认main不变',async t=>{
  const root=await mkdtemp(join(tmpdir(),'openni-doc-source-'));
  t.after(async()=>{
    assert.equal(dirname(resolve(root)),resolve(tmpdir()));
    assert.ok(basename(root).startsWith('openni-doc-source-'));
    await rm(root,{recursive:true,force:true});
  });
  await mkdir(join(root,'docs'));
  await writeFile(join(root,'docs/index.md'),'# 项目介绍\n\n[QA 报告](qa/ui-review.md#screens)\n\n[界面源码](../apps/mobile/lib/ui.dart#L20)\n\n[快速开始](01-quickstart.md)\n');
  await writeFile(join(root,'docs/01-quickstart.md'),'# 本地启动\n');
  const sourceBase='https://github.com/nph-cn/openni-club/blob/codex/openni-ui-20261116/';
  await buildDocs({root,outDir:'preview',sourceBase});
  const html=await readFile(join(root,'preview/index.html'),'utf8');
  assert.ok(html.includes(`href="${sourceBase}docs/qa/ui-review.md#screens"`));
  assert.ok(html.includes(`href="${sourceBase}apps/mobile/lib/ui.dart#L20"`));
  assert.ok(html.includes(`href="${sourceBase}docs/index.md" target="_blank" rel="noreferrer">在 GitHub 查看此页`));
  assert.ok(html.includes('href="/guide/01-quickstart.html"'));
  assert.ok(html.includes('href="https://github.com/nph-cn/openni-club/blob/main/LICENSE"'));
  await buildDocs({root,outDir:'default'});
  const normal=await readFile(join(root,'default/index.html'),'utf8');
  assert.ok(normal.includes('href="https://github.com/nph-cn/openni-club/blob/main/docs/qa/ui-review.md#screens"'));
  assert.ok(normal.includes('href="https://github.com/nph-cn/openni-club/blob/main/docs/index.md"'));
});
