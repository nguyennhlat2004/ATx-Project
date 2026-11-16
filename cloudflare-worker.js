// Worker riêng tư cho bản sao lưu playlist. Gắn R2 binding tên MUSIC_BUCKET.
// Tạo secret MUSIC_TOKEN và biến ALLOWED_ORIGINS (các origin HTTPS cách nhau bằng dấu phẩy).
const MAX_FILE_BYTES = 90 * 1024 * 1024;
const MAX_MANIFEST_BYTES = 1024 * 1024;
const validId = id => /^[A-Za-z0-9_-]{1,128}$/.test(id || '');

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const allow = (env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
    const originAllowed = !origin || allow.includes(origin);
    const cors = new Headers({ 'Cache-Control': 'no-store', 'Vary': 'Origin' });
    if (origin && originAllowed) {cors.set('Access-Control-Allow-Origin', origin);cors.set('Access-Control-Expose-Headers','ETag');}
    const reply = (body, status = 200, extra = {}) => {
      const headers = new Headers(cors); for (const [k, v] of Object.entries(extra)) headers.set(k, v);
      return new Response(body, { status, headers });
    };
    if (!originAllowed) return reply('Origin không được phép', 403);
    if (request.method === 'OPTIONS') {
      cors.set('Access-Control-Allow-Methods', 'GET, HEAD, PUT, OPTIONS');
      cors.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, If-Match, If-None-Match');
      cors.set('Access-Control-Max-Age', '600');
      return new Response(null, { status: 204, headers: cors });
    }
    if (!env.MUSIC_BUCKET || !env.MUSIC_TOKEN || env.MUSIC_TOKEN.length < 32) return reply('Worker chưa cấu hình đầy đủ', 503);
    const token = request.headers.get('Authorization') || '';
    // So sánh các hash có độ dài cố định, không ghi token vào log.
    const enc = new TextEncoder();
    const [a,b] = await Promise.all([crypto.subtle.digest('SHA-256', enc.encode(token)), crypto.subtle.digest('SHA-256', enc.encode('Bearer ' + env.MUSIC_TOKEN))]);
    const aa = new Uint8Array(a), bb = new Uint8Array(b); let difference = 0;
    for (let i = 0; i < aa.length; i++) difference |= aa[i] ^ bb[i];
    if (difference) return reply('Không được phép', 401);
    const url = new URL(request.url), parts = url.pathname.split('/').filter(Boolean);
    if (request.method === 'GET' && parts.length === 1 && parts[0] === 'health') return reply(JSON.stringify({ok:true,syncVersion:2}), 200, {'Content-Type':'application/json'});
    if (request.method === 'GET' && parts.length === 1 && parts[0] === 'playlists') {
      const page = await env.MUSIC_BUCKET.list({prefix:'playlists/', limit:1000});
      const ids = page.objects.map(o=>o.key.slice('playlists/'.length).replace(/\.json$/, '')).filter(validId);
      return reply(JSON.stringify({ids,truncated:page.truncated}),200,{'Content-Type':'application/json'});
    }
    // Tài liệu đồng bộ được cập nhật có điều kiện để không ghi đè thay đổi từ thiết bị khác.
    if (parts.length === 1 && parts[0] === 'sync-state') {
      if (request.method === 'GET') {
        const object = await env.MUSIC_BUCKET.get('sync/state.json');
        return object ? reply(object.body,200,{'Content-Type':'application/json','ETag':object.httpEtag}) : reply('Chưa có dữ liệu đồng bộ',404);
      }
      if (request.method === 'PUT') {
        if (!request.headers.has('If-Match') && request.headers.get('If-None-Match') !== '*') return reply('Cần điều kiện phiên bản',428);
        const size=Number(request.headers.get('Content-Length'));if(!Number.isFinite(size)||size<=0||size>5*1024*1024)return reply('Dữ liệu không hợp lệ hoặc quá lớn',413);
        let value;try{value=await request.json();}catch{return reply('JSON không hợp lệ',400);}
        if(value?.version!==2 || !Array.isArray(value.collections) || !Array.isArray(value.tracks) || !Array.isArray(value.trash) || value.tracks.length>5000 || value.trash.length>5000 || value.collections.length>500 || value.tracks.some(t=>!validId(t.id)||!validId(t.fileKey)||!validId(t.waveKey)))return reply('Trạng thái không hợp lệ',400);
        // The server owns retired IDs. A stale device may not resurrect an object
        // after the collector has made it eligible for physical deletion.
        const previous=await env.MUSIC_BUCKET.get('sync/state.json');
        if(previous ? request.headers.get('If-Match')!==previous.httpEtag : request.headers.get('If-None-Match')!=='*')return reply('Dữ liệu R2 đã đổi trên thiết bị khác',412);
        let old={};if(previous){try{old=JSON.parse(await previous.text());}catch{return reply('Trạng thái R2 bị lỗi',500);}}
        const retiredFiles=Array.isArray(old.retiredFiles)?old.retiredFiles:[],retiredWaves=Array.isArray(old.retiredWaves)?old.retiredWaves:[];
        const files=new Set(retiredFiles),waves=new Set(retiredWaves);
        if(value.tracks.some(t=>files.has(t.fileKey)||waves.has(t.waveKey)))return reply('File đã hết hạn trên R2; không thể ghi đè bằng bản cũ',410);
        value.retiredFiles=retiredFiles;value.retiredWaves=retiredWaves;
        value.pendingPurge=Array.isArray(old.pendingPurge)?old.pendingPurge:[];
        const object=await env.MUSIC_BUCKET.put('sync/state.json',JSON.stringify(value),{onlyIf:request.headers,httpMetadata:{contentType:'application/json'}});
        if(!object)return reply('Dữ liệu R2 đã đổi trên thiết bị khác',412);
        return reply(JSON.stringify({ok:true}),200,{'Content-Type':'application/json','ETag':object.httpEtag});
      }
      return reply('Phương thức không hỗ trợ',405);
    }
    if(parts.length===2 && ['sync-files','sync-waves'].includes(parts[0]) && validId(parts[1])) {
      const key='sync/'+parts[0]+'/'+parts[1], isWave=parts[0]==='sync-waves';
      if(request.method==='GET'){const object=await env.MUSIC_BUCKET.get(key);return object?reply(object.body,200,{'Content-Type':isWave?'application/json':'application/octet-stream','Content-Length':String(object.size)}):reply('Không tìm thấy',404);}
      if(request.method==='HEAD'){const object=await env.MUSIC_BUCKET.head(key);return object?reply(null,200,{'Content-Length':String(object.size)}):reply(null,404);}
      if(request.method==='PUT'){
        const size=Number(request.headers.get('Content-Length'));if(!Number.isFinite(size)||size<=0)return reply('Cần Content-Length',411);
        if(size>(isWave?2*1024*1024:MAX_FILE_BYTES))return reply('File quá lớn',413);
        const result=await env.MUSIC_BUCKET.put(key,request.body,{onlyIf:new Headers({'If-None-Match':'*'}),httpMetadata:{contentType:isWave?'application/json':'application/octet-stream'}});
        return result?reply(JSON.stringify({ok:true}),200,{'Content-Type':'application/json','ETag':result.httpEtag}):reply('Mã file đã tồn tại',409);
      }
      return reply('Phương thức không hỗ trợ',405);
    }
    if (parts.length !== 2 || !['tracks','playlists'].includes(parts[0]) || !validId(parts[1])) return reply('Không tìm thấy',404);
    const isPlaylist = parts[0] === 'playlists', key = parts[0] + '/' + parts[1] + (isPlaylist ? '.json' : '');
    if (request.method === 'GET') {
      const object = await env.MUSIC_BUCKET.get(key);if (!object) return reply('Không tìm thấy',404);
      return reply(object.body,200,{'Content-Type':isPlaylist?'application/json':'application/octet-stream','Content-Length':String(object.size)});
    }
    if (request.method === 'PUT') {
      const size = Number(request.headers.get('Content-Length'));
      if (!Number.isFinite(size) || size <= 0) return reply('Cần Content-Length',411);
      if (size > (isPlaylist ? MAX_MANIFEST_BYTES : MAX_FILE_BYTES)) return reply('File quá lớn',413);
      if (isPlaylist) {
        let value;try { value = await request.json(); } catch { return reply('JSON không hợp lệ',400); }
        if (!value || value.version !== 1 || !Array.isArray(value.tracks) || value.tracks.length > 1000 || value.tracks.some(t=>!validId(t.cloudKey))) return reply('Danh sách không hợp lệ',400);
        await env.MUSIC_BUCKET.put(key,JSON.stringify(value),{httpMetadata:{contentType:'application/json'}});
      } else {
        if (!request.body) return reply('Thiếu file',400);
        await env.MUSIC_BUCKET.put(key,request.body,{httpMetadata:{contentType:'application/octet-stream'}});
      }
      return reply(JSON.stringify({ok:true}),200,{'Content-Type':'application/json'});
    }
    return reply('Phương thức không hỗ trợ',405);
  },
  async scheduled(controller,env,ctx){ctx.waitUntil(purgeExpiredTrash(env.MUSIC_BUCKET,Date.now()));}
};

// Retire keys atomically in the manifest before deleting the objects. The PUT
// endpoint preserves these tombstones and rejects stale references. Pending work
// remains in the manifest if the Worker crashes, so a later cron retries it.
async function purgeExpiredTrash(bucket,now) {
  if(!bucket)return;const object=await bucket.get('sync/state.json');if(!object || !object.body)return;
  let state;try{state=JSON.parse(await object.text());}catch{return;}
  if(state?.version!==2 || !Array.isArray(state.trash) || !Array.isArray(state.tracks)||!Array.isArray(state.collections))return;
  const expired=state.trash.filter(t=>Number.isFinite(t.deletedAt) && t.deletedAt+30*86400000<=now),keep=state.trash.filter(t=>!expired.includes(t));
  const referenced=new Set();for(const p of state.collections)for(const id of (Array.isArray(p.ids)?p.ids:[]))referenced.add(id);for(const t of keep)if(t.trackId)referenced.add(t.trackId);
  const removed=expired.length?state.tracks.filter(t=>!referenced.has(t.id)):[],retained=state.tracks.filter(t=>!removed.includes(t));
  const usedFiles=new Set(retained.map(t=>t.fileKey)),usedWaves=new Set(retained.map(t=>t.waveKey));
  const files=new Set(Array.isArray(state.retiredFiles)?state.retiredFiles:[]),waves=new Set(Array.isArray(state.retiredWaves)?state.retiredWaves:[]);
  const pending=new Set(Array.isArray(state.pendingPurge)?state.pendingPurge:[]);
  for(const t of removed){if(validId(t.fileKey)&&!usedFiles.has(t.fileKey)){files.add(t.fileKey);pending.add('sync/sync-files/'+t.fileKey);}if(validId(t.waveKey)&&!usedWaves.has(t.waveKey)){waves.add(t.waveKey);pending.add('sync/sync-waves/'+t.waveKey);}}
  if(!expired.length&&!pending.size)return;
  const newState={...state,trash:keep,tracks:retained,retiredFiles:[...files],retiredWaves:[...waves],pendingPurge:[...pending]};
  const written=await bucket.put('sync/state.json',JSON.stringify(newState),{onlyIf:{etagMatches:object.etag},httpMetadata:{contentType:'application/json'}});if(!written)return;
  const keys=[...pending].filter(k=>/^sync\/sync-(files|waves)\/[A-Za-z0-9_-]{1,128}$/.test(k));
  for(let i=0;i<keys.length;i+=100)await bucket.delete(keys.slice(i,i+100));
  // Only clear the pending list if no other writer has changed the manifest.
  newState.pendingPurge=[];
  await bucket.put('sync/state.json',JSON.stringify(newState),{onlyIf:{etagMatches:written.etag},httpMetadata:{contentType:'application/json'}});
}
