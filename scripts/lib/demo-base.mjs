export function withDemoBaseHref(html) {
  const bases = [...html.matchAll(/<base\s+href\s*=\s*(["'])(.*?)\1\s*\/?>/gi)];
  if (bases.length !== 1) {
    throw new Error('Flutter Web index.html 必须恰好包含一个 <base href>');
  }
  return html.replace(bases[0][0], '<base href="/demo/">');
}
