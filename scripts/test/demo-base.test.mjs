import test from 'node:test';
import assert from 'node:assert/strict';
import {withDemoBaseHref} from '../lib/demo-base.mjs';

test('packaged Flutter demo resolves its bootstrap inside /demo/', () => {
  const html = withDemoBaseHref('<base href="/">\n<script src="flutter_bootstrap.js"></script>');
  const base = html.match(/<base href="([^"]+)">/)?.[1];
  assert.equal(base, '/demo/');
  assert.equal(new URL('flutter_bootstrap.js', new URL(base, 'https://openni.im')).pathname, '/demo/flutter_bootstrap.js');
  assert.equal(withDemoBaseHref(html), html);
});

test('missing or ambiguous Flutter base href fails packaging', () => {
  assert.throws(() => withDemoBaseHref('<script src="flutter_bootstrap.js"></script>'));
  assert.throws(() => withDemoBaseHref('<base href="/"><base href="/demo/">'));
});
