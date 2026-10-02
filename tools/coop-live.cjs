// End-to-end QA against the real project. Creates only disposable test users/data.
const {chromium}=require('playwright');
const crypto=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const apiKey='AIzaSyBYZshkCJotuezsj1ZhlYspr_GP1DSkeqE';
const base='https://firestore.googleapis.com/v1/projects/nova-5d1c5/databases/(default)/documents/';
const out=path.resolve(__dirname,'../releases');
const accounts=[];
let browser,room;
async function identity(page) {
  return page.evaluate(()=>new Promise((resolve,reject)=>{
    const request=indexedDB.open('firebaseLocalStorageDb');
    request.onerror=()=>reject(Error('Auth storage unavailable'));
    request.onsuccess=()=>{
      const db=request.result,r=db.transaction('firebaseLocalStorage','readonly').objectStore('firebaseLocalStorage').getAll();
      r.onsuccess=()=>{const user=r.result.find(x=>x.value?.stsTokenManager)?.value;db.close();resolve(user?{uid:user.uid,token:user.stsTokenManager.accessToken}:null);};
      r.onerror=()=>reject(Error('Auth lookup failed'));
    };
  }));
}
async function document(p,auth,method='GET') {
  const response=await fetch(base+p,{method,headers:{Authorization:'Bearer '+auth.token}});
  if(!response.ok) throw Error(`${method} ${p}: HTTP ${response.status}`);
  return method==='GET'?response.json():null;
}
async function world(auth) {const d=await document(`umbralRoomsV1/${room}/state/world`,auth);return JSON.parse(d.fields.payload.stringValue);}
async function open(page) {
  await page.goto('http://localhost:8175',{waitUntil:'networkidle'});
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
  await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
  await page.getByRole('button',{name:'Firebase · Nube y cooperativo'}).click();
  await page.getByRole('button',{name:'Crear cuenta'}).waitFor({timeout:45000});
}
async function localSave(page) {return page.evaluate(()=>{const raw=JSON.parse(localStorage.getItem('flutter.umbral.save.v1'));return typeof raw==='string'?JSON.parse(raw):raw;});}
async function type(page,label,text) {await page.getByRole('textbox',{name:label}).click();await page.keyboard.press('Control+A');await page.keyboard.type(text,{delay:10});}
(async()=>{
  fs.mkdirSync(out,{recursive:true});
  browser=await chromium.launch({headless:true,channel:'chrome',args:['--disable-background-timer-throttling','--disable-renderer-backgrounding','--disable-backgrounding-occluded-windows']});
  const ctxA=await browser.newContext({viewport:{width:1280,height:820}}),ctxB=await browser.newContext({viewport:{width:1000,height:760}});
  const a=await ctxA.newPage(),b=await ctxB.newPage(),errors=[];
  for(const p of [a,b]) p.on('pageerror',e=>errors.push(e.message));
  await open(a);accounts.push(await identity(a));
  const email=`umbral-qa-${Date.now()}@example.com`,password=crypto.randomBytes(18).toString('base64url');
  await type(a,'Correo electrónico',email);
  await type(a,'Contraseña (mínimo 8 caracteres)',password);
  await a.getByRole('button',{name:'Crear cuenta',exact:true}).click();
  await a.getByRole('button',{name:'Cerrar sesión',exact:true}).waitFor({timeout:30000});
  accounts[0]=await identity(a);
  await a.getByRole('button',{name:'Crear sala cooperativa'}).click();
  await a.getByRole('button',{name:'Pausa',exact:true}).waitFor({timeout:30000});
  await a.getByRole('button',{name:'Pausa',exact:true}).click();
  const waiting=a.getByLabel(/Código: [A-Z2-9]{6}/);
  await waiting.waitFor({timeout:10000});
  room=(await waiting.getAttribute('aria-label')).match(/Código: ([A-Z2-9]{6})/)[1];
  await a.getByRole('button',{name:'Seguir explorando'}).click();
  await open(b);accounts.push(await identity(b));
  await type(b,'Código de sala',room);
  await b.getByRole('button',{name:'Unirse a la sala'}).click();
  await b.getByRole('button',{name:'Pausa',exact:true}).waitFor({timeout:30000});
  await b.waitForTimeout(2500);
  const before=await world(accounts[0]);
  await b.keyboard.down('d');await b.waitForTimeout(1100);await b.keyboard.up('d');
  await b.waitForTimeout(1200);
  const moved=await world(accounts[0]);
  if(moved.guest.position[0]<before.guest.position[0]+60) throw Error('Guest movement did not reach the authoritative world');
  await b.keyboard.press('i');await b.getByRole('button',{name:'Volver al juego'}).waitFor();
  await b.waitForTimeout(1200);
  const frozen=await world(accounts[0]);await a.waitForTimeout(1000);
  if((await world(accounts[0])).host.clock!==frozen.host.clock) throw Error('Shared pause did not freeze host');
  await b.getByRole('button',{name:'Volver al juego'}).click();
  await a.waitForTimeout(1000);
  await a.keyboard.down('d');await a.waitForTimeout(4900);await a.keyboard.up('d');await a.keyboard.press('f');
  await a.waitForTimeout(1500);
  let shared=await world(accounts[0]);
  if(shared.host.zone!==1||shared.guest.zone!==1) throw Error('Party did not travel together');
  await a.keyboard.down('d');await a.waitForTimeout(2200);await a.keyboard.up('d');
  await b.keyboard.down('d');await b.waitForTimeout(1700);await b.keyboard.up('d');
  await a.keyboard.down(' ');await b.keyboard.down(' ');await b.keyboard.press('q');
  await a.waitForTimeout(3200);await a.keyboard.up(' ');await b.keyboard.up(' ');
  shared=await world(accounts[0]);
  if(shared.host.kills<1||shared.guest.kills<1) throw Error('Shared kills/XP were not awarded');
  await a.screenshot({path:path.join(out,'umbral-020-coop-host.png')});
  await b.screenshot({path:path.join(out,'umbral-020-coop-guest.png')});
  await b.keyboard.press('Escape');await b.getByRole('button',{name:'Guardar y volver al inicio'}).click();
  await b.getByRole('button',{name:/Continuar/}).waitFor();
  await a.waitForTimeout(1000);
  if((await document(`umbralRoomsV1/${room}`,accounts[0])).fields.status.stringValue!=='closed') throw Error('Room did not close');
  await a.keyboard.press('Escape');await a.getByRole('button',{name:'Guardar y volver al inicio'}).click();
  await a.getByRole('button',{name:/Continuar/}).waitFor();
  await a.getByRole('button',{name:'Firebase · Nube y cooperativo'}).click();
  await a.getByRole('button',{name:'Subir partida'}).click();
  await a.getByText('Partida subida. Sincronización automática activada.').waitFor();
  const saved=await localSave(a);
  const ctxC=await browser.newContext({viewport:{width:1000,height:800}}),c=await ctxC.newPage();c.on('pageerror',e=>errors.push(e.message));
  await open(c);accounts.push(await identity(c));
  await type(c,'Correo electrónico',email);
  await type(c,'Contraseña (mínimo 8 caracteres)',password);
  await c.getByRole('button',{name:'Entrar',exact:true}).click();
  await c.getByRole('button',{name:'Cerrar sesión',exact:true}).waitFor();
  await c.getByRole('button',{name:'Restaurar partida'}).click();
  await c.getByRole('button',{name:'Confirmar',exact:true}).click();
  await c.getByText('Progreso restaurado en el dispositivo.').waitFor();
  const restored=await localSave(c);
  if(restored.kills!==saved.kills||restored.gold!==saved.gold||restored.zone!==saved.zone) throw Error('Cross-device save differs');
  await c.screenshot({path:path.join(out,'umbral-020-cloud.png')});
  if(errors.length) throw Error(errors.join('\n'));
  console.log('PASS: Firebase account link/login, two-client room, guest movement, shared pause, party travel, combat rewards, leave, cloud upload and restoration on a third client.');
})().catch(async e=>{
  console.error(e.message);
  if(browser) {let i=0;for(const ctx of browser.contexts()) for(const p of ctx.pages()) {await p.screenshot({path:path.join(out,`coop-diagnostic-${i++}.png`)}).catch(()=>{});}}
  process.exitCode=1;
}).finally(async()=>{
  if(accounts[0]&&room) {
    for(const p of [`umbralRoomsV1/${room}/input/guest`,`umbralRoomsV1/${room}/state/world`,...accounts.slice(1).map(a=>`umbralRoomsV1/${room}/players/${a.uid}`),`umbralRoomsV1/${room}`]) await document(p,accounts[0],'DELETE').catch(()=>{});
  }
  for(const account of accounts.filter(Boolean)) {
    await document(`umbralSavesV1/${account.uid}`,account,'DELETE').catch(()=>{});
    await document(`umbralPresenceV1/${account.uid}`,account,'DELETE').catch(()=>{});
    await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${apiKey}`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({idToken:account.token})}).catch(()=>{});
  }
  await browser?.close();
});
