const {test} = require('node:test');
const assert = require('node:assert/strict');
const {scheduleFields, overlaps, mutateSchedule} = require('./feeder_schedule_mutation');
const {sensorStateChanges, sensorValue} = require('./sensor_alerts');
const {feedingReminderOccurrence} = require('./feeding_reminder');
const {deliverNotificationOnce, notificationEventId} = require('./notification_delivery');

test('schedule time normalization and duplicate day/time regardless of dose', () => {
  const first = scheduleFields({time:'6:00',ampm:'PM',days:'0110000',grams:20});
  assert.equal(first.timeValue,1080);
  assert.ok(overlaps(first,{...first,days:'0101000',grams:40}));
  assert.ok(!overlaps(first,{...first,days:'0001000'}));
  assert.ok(overlaps(first,{time:'6:00',ampm:'PM',grams:60}));
  assert.equal(scheduleFields({time:'12:00',ampm:'AM',days:'1111111'}).timeValue,0);
  for(const grams of [0,-20,21,201,Infinity,'20'])
    assert.throws(()=>scheduleFields({time:'6:00',ampm:'AM',days:'1111111',grams}));
  assert.throws(()=>scheduleFields({time:'6:00',ampm:'AM',days:'0000000'}));
});

test('bad sensor readings do not produce water-quality alarms',()=>{
  const thresholds={dissolved_oxygen:{min:5,max:10},turbidity:{min:0,max:50},feed_level:{min:20,max:100,critical:10}};
  assert.deepEqual(sensorStateChanges({}, {dissolved_oxygen:-1,turbidity:999,turbidity_air:true,feed_level:-1},thresholds),[]);
  assert.equal(sensorValue('dissolved_oxygen',{dissolved_oxygen:null}),null);
  assert.equal(sensorValue('feed_level',{feed_level:101}),null);
  assert.equal(sensorStateChanges({}, {dissolved_oxygen:0},thresholds)[0].state,'critical');
  assert.equal(sensorStateChanges({}, {feed_level:7},thresholds)[0].state,'critical');
  assert.equal(sensorStateChanges({dissolved_oxygen:1}, {dissolved_oxygen:7},thresholds)[0].state,'resolved');
});

test('reminders tolerate late ticks, obey effective time and midnight',()=>{
  const now = Date.parse('2026-09-08T17:57:30+08:00');
  const schedule={timeValue:1080,days:'0010000',enabled:true};
  assert.equal(feedingReminderOccurrence(schedule,now).minutesUntil,3);
  assert.equal(feedingReminderOccurrence({...schedule,effective_at_ms:now+300000},now),null);
  assert.equal(feedingReminderOccurrence(schedule,now+300000),null);
  assert.equal(feedingReminderOccurrence({...schedule,enabled:false},now),null);
  assert.equal(feedingReminderOccurrence({timeValue:0,days:'0001000'},Date.parse('2026-09-08T23:58:00+08:00')).dateKey,'2026-09-09');
});

// Serial transaction adapter: tests mutation behavior and rollback, not an
// emulator substitute for Firestore's concurrency/rules implementation.
function memoryDb(initial={}) {
  const records=new Map(Object.entries(initial)); let id=0, pending=Promise.resolve();
  const collection=path=>({path,doc:(name=`auto${++id}`)=>ref(`${path}/${name}`)});
  const ref=path=>({path,id:path.split('/').pop(),collection:name=>collection(`${path}/${name}`)});
  return {records,collection,runTransaction(callback){
    const run=pending.then(async()=>{
      const draft=new Map(records);
      const tx={get:async target=>target.doc
        ? {docs:[...draft].filter(([key])=>key.startsWith(`${target.path}/`)&&key.slice(target.path.length+1).indexOf('/')<0).map(([key,value])=>({id:key.split('/').pop(),data:()=>value}))}
        : {exists:draft.has(target.path),data:()=>draft.get(target.path)},
        create:(target,data)=>{assert.ok(!draft.has(target.path));draft.set(target.path,data);},
        set:(target,data)=>draft.set(target.path,data),
        update:(target,data)=>draft.set(target.path,{...draft.get(target.path),...data}),
        delete:target=>draft.delete(target.path)};
      const result=await callback(tx);records.clear();for(const [key,value] of draft) records.set(key,value);return result;
    });pending=run.catch(()=>{});return run;
  }};
}

test('transaction mutation rejects overlaps and disabled owners without partial writes',async()=>{
  const db=memoryDb({'users/u':{role:'owner',status:'active'},'tanks/u':{owner_uid:'u',is_initialized:true}});
  const call=input=>mutateSchedule({db,uid:'u',input,timestamp:()=>123,deleteField:()=>null,now:()=>1000});
  const input={operation:'add',time:'6:00',ampm:'PM',days:'0100000',grams:20};
  const outcomes=await Promise.allSettled([call(input),call({...input,grams:40})]);
  assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
  assert.equal(outcomes.find(x=>x.status==='rejected').reason.code,'already-exists');
  assert.equal([...db.records.keys()].filter(x=>x.includes('/feeder_logs/')).length,1);
  const result=await call({...input,days:'0010000'});
  await call({operation:'delete',scheduleId:result.scheduleId});
  db.records.set('users/u',{role:'owner',status:'disabled'});
  await assert.rejects(call({...input,days:'0001000'}),error=>error.code==='permission-denied');
});

test('notification retries preserve read/deleted state and do not resend',async()=>{
  const db=memoryDb();let sends=0;
  const id=notificationEventId('sensor','tank','event');
  const send=()=>deliverNotificationOnce({db,id,uid:'u',type:'warning',title:'Alert',body:'Check',timestamp:()=>123,send:async()=>sends++});
  await Promise.all([send(),send()]);assert.equal(sends,1);
  db.records.get(`notifications/${id}`).is_read=true;
  await send();assert.equal(db.records.get(`notifications/${id}`).is_read,true);
  db.records.delete(`notifications/${id}`);await send();
  assert.ok(!db.records.has(`notifications/${id}`));assert.equal(sends,1);
});
