// Test helper: builds ZIP archives (optionally ZIP64) in memory.
import { deflateRawSync } from 'node:zlib';

export function buildZip(files: { name: string; data: Uint8Array; store?: boolean }[], zip64 = false): Uint8Array {
  const chunks: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  const enc = new TextEncoder();
  for (const f of files) {
    const name = enc.encode(f.name);
    const comp = f.store ? f.data : new Uint8Array(deflateRawSync(f.data));
    const method = f.store ? 0 : 8;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(8, method, true);
    lh.setUint32(18, zip64 ? 0xffffffff : comp.length, true); lh.setUint32(22, zip64 ? 0xffffffff : f.data.length, true);
    lh.setUint16(26, name.length, true); lh.setUint16(28, 0, true);
    chunks.push(new Uint8Array(lh.buffer), name, comp);
    const extra = zip64 ? new DataView(new ArrayBuffer(28)) : undefined;
    if (extra) {
      extra.setUint16(0, 0x0001, true); extra.setUint16(2, 24, true);
      extra.setBigUint64(4, BigInt(f.data.length), true); extra.setBigUint64(12, BigInt(comp.length), true); extra.setBigUint64(20, BigInt(offset), true);
    }
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 45, true); ch.setUint16(6, 20, true); ch.setUint16(10, method, true);
    ch.setUint32(20, zip64 ? 0xffffffff : comp.length, true); ch.setUint32(24, zip64 ? 0xffffffff : f.data.length, true);
    ch.setUint16(28, name.length, true); ch.setUint16(30, extra ? 28 : 0, true);
    ch.setUint32(42, zip64 ? 0xffffffff : offset, true);
    central.push(new Uint8Array(ch.buffer), name, ...(extra ? [new Uint8Array(extra.buffer)] : []));
    offset += 30 + name.length + comp.length;
  }
  const cdSize = central.reduce((t, c) => t + c.length, 0);
  const cdOffset = offset;
  const tail: Uint8Array[] = [];
  if (zip64) {
    const e64 = new DataView(new ArrayBuffer(56));
    e64.setUint32(0, 0x06064b50, true); e64.setBigUint64(4, 44n, true); e64.setUint16(12, 45, true); e64.setUint16(14, 45, true);
    e64.setBigUint64(24, BigInt(files.length), true); e64.setBigUint64(32, BigInt(files.length), true);
    e64.setBigUint64(40, BigInt(cdSize), true); e64.setBigUint64(48, BigInt(cdOffset), true);
    const loc = new DataView(new ArrayBuffer(20));
    loc.setUint32(0, 0x07064b50, true); loc.setBigUint64(8, BigInt(cdOffset + cdSize), true); loc.setUint32(16, 1, true);
    tail.push(new Uint8Array(e64.buffer), new Uint8Array(loc.buffer));
  }
  const eocd = new DataView(new ArrayBuffer(22));
  eocd.setUint32(0, 0x06054b50, true);
  eocd.setUint16(8, zip64 ? 0xffff : files.length, true); eocd.setUint16(10, zip64 ? 0xffff : files.length, true);
  eocd.setUint32(12, zip64 ? 0xffffffff : cdSize, true); eocd.setUint32(16, zip64 ? 0xffffffff : cdOffset, true);
  tail.push(new Uint8Array(eocd.buffer));
  const all = [...chunks, ...central, ...tail];
  const out = new Uint8Array(all.reduce((t, c) => t + c.length, 0));
  let p = 0;
  for (const c of all) { out.set(c, p); p += c.length; }
  return out;
}

export async function streamToText(s: ReadableStream<Uint8Array>): Promise<string> {
  const r = s.getReader();
  const dec = new TextDecoder();
  let out = '';
  for (;;) { const { value, done } = await r.read(); if (done) break; out += dec.decode(value, { stream: true }); }
  return out + dec.decode();
}
