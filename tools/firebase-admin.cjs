// Credentials stay in the Firebase CLI credential store, never in sources/APKs.
const fs = require('node:fs');
const path = require('node:path');
const {Client} = require('firebase-tools/lib/apiv2');
const {getGlobalDefaultAccount} = require('firebase-tools/lib/auth');
const {requireAuth} = require('firebase-tools/lib/requireAuth');
const root=path.resolve(__dirname,'..'), project='nova-5d1c5';
(async()=>{
  await requireAuth({...getGlobalDefaultAccount(),project});
  const mode=process.argv[2];
  if(mode==='apps') {
    const api=new Client({urlPrefix:'https://firebase.googleapis.com',apiVersion:'v1beta1'});
    const apps=(await api.get(`/projects/${project}/androidApps`)).body.apps||[];
    let app=apps.find(a=>a.packageName==='dev.umbral.umbral_rpg');
    if(!app) {
      await api.post(`/projects/${project}/androidApps`,{displayName:'Umbral RPG',packageName:'dev.umbral.umbral_rpg'});
      console.log('Android app registration requested. Run apps again to fetch its config.'); return;
    }
    const config=(await api.get(`/${app.name}/config`)).body;
    const json=JSON.parse(Buffer.from(config.configFileContents,'base64').toString());
    const client=json.client.find(c=>c.client_info.android_client_info.package_name==='dev.umbral.umbral_rpg');
    const web=(await api.get(`/projects/${project}/webApps`)).body.apps;
    const wconfig=(await api.get(`/${web[0].name}/config`)).body;
    fs.writeFileSync(path.join(root,'.tmp/firebase-apps.json'), JSON.stringify({android:{apiKey:client.api_key[0].current_key,appId:client.client_info.mobilesdk_app_id},web:{apiKey:wconfig.apiKey,appId:wconfig.appId}},null,2));
    console.log('Public Firebase app configuration saved to .tmp/firebase-apps.json');
    const auth=new Client({urlPrefix:'https://identitytoolkit.googleapis.com',apiVersion:'admin/v2'});
    await auth.patch(`/projects/${project}/config`,{signIn:{email:{enabled:true,passwordRequired:true}}},{queryParams:{updateMask:'signIn.email.enabled,signIn.email.passwordRequired'}});
    console.log('Email/password accounts enabled.'); return;
  }
  const api=new Client({urlPrefix:'https://firebaserules.googleapis.com',apiVersion:'v1'});
  const release=(await api.get(`/projects/${project}/releases/cloud.firestore`)).body;
  const source=(await api.get('/'+release.rulesetName)).body.source.files[0].content;
  const backup=path.join(root,'.tmp/rules-before-umbral-020.rules'), target=path.join(root,'firestore.rules');
  if(mode==='prepare') {
    const begin='    // BEGIN UMBRAL RPG', end='    // END UMBRAL RPG';
    const addition=fs.readFileSync(path.join(root,'umbral.rules'),'utf8');
    const start=source.indexOf(begin), finish=source.indexOf(end);
    let merged;
    if(start>=0 && finish>start) merged=source.slice(0,start)+addition+source.slice(finish+end.length);
    else {
      const insertion=source.lastIndexOf('}',source.lastIndexOf('}')-1);
      if(insertion<0) throw Error('Unexpected shared rules structure');
      merged=source.slice(0,insertion)+addition+'\n'+source.slice(insertion);
    }
    fs.writeFileSync(backup,source); fs.writeFileSync(target,merged);
    console.log('Prepared current shared rules; only Umbral block added/replaced.');
  } else if(mode==='deploy') {
    if(source!==fs.readFileSync(backup,'utf8')) throw Error('Remote rules changed: prepare and test again');
    const content=fs.readFileSync(target,'utf8');
    const set=(await api.post(`/projects/${project}/rulesets`,{source:{files:[{name:'firestore.rules',content}]}})).body;
    await api.patch(`/projects/${project}/releases/cloud.firestore`,{release:{name:release.name,rulesetName:set.name},updateMask:'rulesetName'});
    console.log('Deployed Umbral with remote revision guard.');
  } else if(mode==='verify') {
    if(source!==fs.readFileSync(target,'utf8')) throw Error('Remote/local rules differ');
    console.log('PASS: deployed shared rules exactly match validated local rules.');
  } else throw Error('Use apps, prepare, deploy or verify');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
