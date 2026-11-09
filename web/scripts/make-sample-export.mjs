// Generates a realistic synthetic Apple Health export.zip for demos / E2E tests.
// Usage: node scripts/make-sample-export.mjs out.zip [days]
import { writeFileSync } from 'node:fs';
import { deflateRawSync } from 'node:zlib';

const out = process.argv[2] ?? 'sample-export.zip';
const DAYS = Number(process.argv[3] ?? 75);
let seed = 42;
const rnd = () => ((seed = (1103515245 * seed + 12345) % 2 ** 31) / 2 ** 31);
const pad = (n) => String(n).padStart(2, '0');
const fmt = (ms) => { const d = new Date(ms); return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}:${pad(d.getUTCSeconds())} +0000`; };
const watch = `sourceName="Alex's Apple Watch" device="&lt;&lt;HKDevice: 0x1&gt;, name:Apple Watch, manufacturer:Apple Inc., model:Watch, hardware:Watch7,5&gt;"`;
const phone = `sourceName="Alex's iPhone" device="&lt;&lt;HKDevice: 0x2&gt;, name:iPhone, manufacturer:Apple Inc., model:iPhone&gt;"`;
const oura = `sourceName="Oura" device="&lt;&lt;HKDevice: 0x3&gt;, name:Oura Ring, manufacturer:Oura, model:Gen3&gt;"`;
const end = Date.UTC(2026, 9, 31, 20, 0, 0);
const start = end - DAYS * 86400_000;
const parts = [`<?xml version="1.0" encoding="UTF-8"?>\n<HealthData locale="en_US">\n<ExportDate value="${fmt(end)}"/>\n<Me HKCharacteristicTypeIdentifierDateOfBirth="1990-04-12" HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexMale"/>\n`];
const rec = (type, src, unit, s, e, v, meta = '') => parts.push(`<Record type="${type}" ${src} unit="${unit}" startDate="${fmt(s)}" endDate="${fmt(e)}" value="${v}">${meta}</Record>\n`);
for (let d = 0; d < DAYS; d++) {
  const day0 = start + d * 86400_000 - ((start + d * 86400_000) % 86400_000);
  const late = d % 4 === 0;
  // Sleep (watch stages + Oura overlap), 23:00 → ~06:45
  const bed = day0 - 3600_000 + (rnd() * 40 - 20) * 60_000;
  const plan = [[3, 0.3], [4, 0.17], [3, 0.18], [5, 0.12], [2, 0.03], [3, 0.1], [5, 0.1]];
  const total = (430 + rnd() * 60 - (late ? 20 : 0)) * 60_000;
  let t = bed;
  const stage = { 2: 'Awake', 3: 'AsleepCore', 4: 'AsleepDeep', 5: 'AsleepREM' };
  for (const [s, f] of plan) {
    parts.push(`<Record type="HKCategoryTypeIdentifierSleepAnalysis" ${watch} startDate="${fmt(t)}" endDate="${fmt(t + total * f)}" value="HKCategoryValueSleepAnalysis${stage[s]}"/>\n`);
    t += total * f;
  }
  parts.push(`<Record type="HKCategoryTypeIdentifierSleepAnalysis" ${oura} startDate="${fmt(bed - 600_000)}" endDate="${fmt(t + 900_000)}" value="HKCategoryValueSleepAnalysisAsleepCore"/>\n`);
  rec('HKQuantityTypeIdentifierHeartRateVariabilitySDNN', watch, 'ms', day0 + 3 * 3600_000, day0 + 3 * 3600_000 + 60_000, (52 + rnd() * 8 - 4 - (d > 0 && (d - 1) % 4 === 0 ? 8 : 0)).toFixed(1));
  rec('HKQuantityTypeIdentifierRestingHeartRate', watch, 'count/min', day0 + 8 * 3600_000, day0 + 8 * 3600_000, (55 + rnd() * 3).toFixed(0));
  // Daytime HR every 5 min 07:00–22:00, + workout
  for (let m = 7 * 60; m < 22 * 60; m += 5) {
    const ts = day0 + m * 60_000;
    rec('HKQuantityTypeIdentifierHeartRate', watch, 'count/min', ts, ts, (70 + rnd() * 15).toFixed(0));
  }
  const wStart = day0 + (late ? 19.5 : 7) * 3600_000;
  for (let s = 0; s < 45 * 60; s += 30) rec('HKQuantityTypeIdentifierHeartRate', watch, 'count/min', wStart + s * 1000, wStart + s * 1000, (125 + Math.min(30, s / 60) + rnd() * 5).toFixed(0));
  parts.push(`<Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="45" durationUnit="min" ${watch} startDate="${fmt(wStart)}" endDate="${fmt(wStart + 2700_000)}"><WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" sum="${(380 + rnd() * 80).toFixed(0)}" unit="kcal"/><WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" average="145" unit="count/min"/></Workout>\n`);
  // Steps hourly from watch + overlapping iPhone
  for (let h = 7; h < 22; h++) {
    const v = Math.round(200 + rnd() * 900 + (h === 8 || h === 12 ? 800 : 0));
    rec('HKQuantityTypeIdentifierStepCount', watch, 'count', day0 + h * 3600_000, day0 + (h + 1) * 3600_000, v);
    if (h % 2 === 0) rec('HKQuantityTypeIdentifierStepCount', phone, 'count', day0 + h * 3600_000, day0 + (h + 1) * 3600_000, Math.round(v * 0.9));
    rec('HKQuantityTypeIdentifierActiveEnergyBurned', watch, 'kcal', day0 + h * 3600_000, day0 + (h + 1) * 3600_000, (15 + rnd() * 20).toFixed(1));
  }
  rec('HKQuantityTypeIdentifierAppleExerciseTime', watch, 'min', wStart, wStart + 2700_000, 45);
  if (d % 3 === 0) rec('HKQuantityTypeIdentifierBodyMass', `sourceName="Withings"`, 'kg', day0 + 7 * 3600_000, day0 + 7 * 3600_000, (78 - d * 0.02 + rnd() * 0.4).toFixed(2));
  rec('HKQuantityTypeIdentifierDietaryWater', phone, 'mL', day0 + 12 * 3600_000, day0 + 12 * 3600_000, 1500 + Math.round(rnd() * 800), '<MetadataEntry key="HKWasUserEntered" value="1"/>');
  const ds = `${new Date(day0).getUTCFullYear()}-${pad(new Date(day0).getUTCMonth() + 1)}-${pad(new Date(day0).getUTCDate())}`;
  parts.push(`<ActivitySummary dateComponents="${ds}" activeEnergyBurned="${(450 + rnd() * 200).toFixed(1)}" activeEnergyBurnedGoal="500" appleExerciseTime="${45 + Math.round(rnd() * 15)}" appleExerciseTimeGoal="30" appleStandHours="${9 + Math.round(rnd() * 4)}" appleStandHoursGoal="12"/>\n`);
}
parts.push('</HealthData>\n');
const xml = Buffer.from(parts.join(''));
const files = [{ name: 'apple_health_export/export.xml', data: xml }, { name: 'apple_health_export/export_cda.xml', data: Buffer.from('<cda/>') }];
const chunks = [], central = [];
let offset = 0;
for (const f of files) {
  const name = Buffer.from(f.name), comp = deflateRawSync(f.data);
  const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(8, 8);
  lh.writeUInt32LE(comp.length, 18); lh.writeUInt32LE(f.data.length, 22); lh.writeUInt16LE(name.length, 26);
  chunks.push(lh, name, comp);
  const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(8, 10);
  ch.writeUInt32LE(comp.length, 20); ch.writeUInt32LE(f.data.length, 24); ch.writeUInt16LE(name.length, 28); ch.writeUInt32LE(offset, 42);
  central.push(ch, name);
  offset += 30 + name.length + comp.length;
}
const cd = Buffer.concat(central);
const eocd = Buffer.alloc(22); eocd.writeUInt32LE(0x06054b50, 0); eocd.writeUInt16LE(files.length, 8); eocd.writeUInt16LE(files.length, 10);
eocd.writeUInt32LE(cd.length, 12); eocd.writeUInt32LE(offset, 16);
writeFileSync(out, Buffer.concat([...chunks, cd, eocd]));
console.log(`wrote ${out}: ${(xml.length / 1e6).toFixed(1)} MB XML, ${DAYS} days`);
