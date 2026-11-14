import {existsSync,readFileSync} from 'node:fs';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const brandFields=['id','clubId','name','shortName','tagline','description','city','notice','primaryColor','logoUrl','logoAsset','legalEntity','supportContact','privacyText','termsText','demoData','configHash'];
export function readBranding(env){
  const root=fileURLToPath(new URL('../../../',import.meta.url));
  const choose=(value,fallback)=>value==='none'?null:value?resolve(value):existsSync(fallback)?fallback:null;
  const path=choose(env.CLUB_CONFIG_PATH,join(root,'generated/club/public.json'));
  const seedPath=env.CLUB_CONFIG_PATH==='none'&&!env.CLUB_SEED_PATH?null:choose(env.CLUB_SEED_PATH,join(root,'generated/club/seed.json'));
  function read(path,label){if(!path)return null;try{const data=JSON.parse(readFileSync(path,'utf8'));if(!data||typeof data!=='object'||Array.isArray(data))throw Error();return data;}catch{throw Error(`Unable to read valid ${label} JSON`);}}
  const input=read(path,'CLUB_CONFIG_PATH');let publicBrand=null;
  if(input){
    if(typeof input.name!=='string'||!input.name.trim()||typeof input.demoData!=='boolean')throw Error('Club branding must include name and boolean demoData');
    publicBrand={};for(const field of brandFields)if(input[field]!==undefined)publicBrand[field]=input[field];
  }
  const initialSeed=read(seedPath,'CLUB_SEED_PATH');
  if(initialSeed&&(!initialSeed.club||['services','players','announcements'].some(key=>!Array.isArray(initialSeed[key]))))throw Error('Club seed must include club, services, players and announcements');
  let brandLogo=null;
  if(path&&existsSync(join(dirname(path),'logo.png'))){const bytes=readFileSync(join(dirname(path),'logo.png'));if(bytes.length<=4*1024*1024&&bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])))brandLogo=bytes;}
  return {publicBrand,initialSeed,brandConfigPath:path,brandLogo};
}
