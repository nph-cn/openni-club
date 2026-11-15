import {resolve} from 'node:path';
import {createPreviewServer} from './lib/preview-server.mjs';

const root = resolve('dist');
const port = Number(process.env.WEB_PORT || 4173);

createPreviewServer({root}).listen(port, '127.0.0.1', () => {
  console.log(`OpenNI preview http://127.0.0.1:${port}`);
});
