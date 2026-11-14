import test from 'node:test';
import assert from 'node:assert/strict';
import {apiAddress,safeImage,shanghaiInput,fromShanghaiInput,money} from '../../apps/admin/ui.js';
test('admin accepts TLS APIs or loopback only, without URL credentials',()=>{
 assert.equal(apiAddress('https://api.club.example/api/v1/'),'https://api.club.example/api/v1');
 assert.equal(apiAddress('http://127.0.0.1:8790/api/v1'),'http://127.0.0.1:8790/api/v1');
 for(const url of ['http://api.example/api/v1','https://secret@example.com/api/v1','https://api.example/api/v1?token=secret','https://api.example/api/v1#token','https://api.example/wrong'])assert.throws(()=>apiAddress(url));
});
test('Shanghai availability input is independent of browser timezone',()=>{
 assert.equal(shanghaiInput('2026-11-15T12:30:00.000Z'),'2026-11-15T20:30');
 assert.equal(fromShanghaiInput('2026-11-15T20:30'),'2026-11-15T12:30:00.000Z');
 assert.throws(()=>fromShanghaiInput('tomorrow'));
 assert.equal(money(3900),'¥39');assert.equal(money(3950),'¥39.50');
});
test('empty images and dangerous URI schemes do not become requests',()=>{
 globalThis.location={origin:'https://club.example'};
 for(const value of [null,undefined,'','  ','javascript:alert(1)','data:image/svg+xml,<svg/>','http://foreign.example/image'])assert.equal(safeImage(value),'');
 assert.equal(safeImage('/brand.png'),'https://club.example/brand.png');
 assert.equal(safeImage('https://cdn.example/logo.png'),'https://cdn.example/logo.png');
 delete globalThis.location;
});
