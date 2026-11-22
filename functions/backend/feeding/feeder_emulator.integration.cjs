// Explicit emulator-only integration test. Never falls back to a live project.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const {mutateSchedule} = require('./feeder_schedule_mutation');
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host || !/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local Firestore emulator required');
const projectId = 'demo-craycare-tests';
admin.initializeApp({projectId});
const db=admin.firestore();

function token(uid, extra={}) {
  const now=Math.floor(Date.now()/1000);
  const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({alg:'none',typ:'JWT'})}.${encode({iss:`https://securetoken.google.com/${projectId}`,aud:projectId,sub:uid,user_id:uid,iat:now,exp:now+3600,auth_time:now,firebase:{sign_in_provider:'password'},...extra})}.`;
}
async function writeAs(uid, path, fields, expected, extra={}, mask='') {
  const response=await fetch(`http://${host}/v1/projects/${projectId}/databases/(default)/documents/${path}${mask}`, {
    method:'PATCH',headers:{Authorization:`Bearer ${token(uid,extra)}`,'Content-Type':'application/json'},body:JSON.stringify({fields}),
  });
  const text=await response.text();assert.equal(response.status,expected,`${path}: ${text}`);
}

async function main(){
  await db.doc('users/owner').set({role:'owner',status:'active'});
  await db.doc('tanks/owner').set({owner_uid:'owner',is_initialized:true});
  await db.doc('hardware_system/currentOwner').set({tank_id:'owner',owner_uid:'owner'});
  const mutation=input=>mutateSchedule({db,uid:'owner',input,timestamp:()=>admin.firestore.FieldValue.serverTimestamp(),deleteField:()=>admin.firestore.FieldValue.delete()});
  const input={operation:'add',time:'6:00',ampm:'PM',days:'0100000',grams:20};
  const results=await Promise.allSettled([mutation(input),mutation({...input,grams:40})]);
  assert.equal(results.filter(result=>result.status==='fulfilled').length,1);
  assert.equal(results.find(result=>result.status==='rejected').reason.code,'already-exists');
  const scheduleId=results.find(result=>result.status==='fulfilled').value.scheduleId;
  assert.equal((await db.collection('tanks/owner/feeder_logs').get()).size,1);
  await mutation({...input,days:'0010000'});
  await writeAs('owner','tanks/owner/feeder_schedules/direct',{enabled:{booleanValue:true}},403);
  await writeAs('owner',`tanks/owner/feeder_schedules/${scheduleId}`,{enabled:{booleanValue:false}},403,{},'?updateMask.fieldPaths=enabled');
  await writeAs('owner','tanks/owner/feeder/schedule_guard',{revision:{integerValue:'99'}},403);
  await writeAs('esp',`tanks/owner/feeder_schedules/${scheduleId}`,{isDone:{booleanValue:true}},200,{email:'esp32@craycare.com'},'?updateMask.fieldPaths=isDone');
  await writeAs('esp',`tanks/owner/feeder_schedules/${scheduleId}`,{grams:{integerValue:'200'}},403,{email:'esp32@craycare.com'},'?updateMask.fieldPaths=grams');
  await db.doc('users/owner').update({status:'disabled'});
  await assert.rejects(mutation({...input,days:'0001000'}),error=>error.code==='permission-denied');
  console.log('PASS: Firestore concurrent mutation, atomic audit, owner/ESP rules and disabled owner checks');
}
main().then(()=>admin.app().delete()).catch(error=>{console.error(error);process.exitCode=1;return admin.app().delete();});
