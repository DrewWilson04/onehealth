// Minimal streaming ZIP reader (ZIP64-capable) for Apple Health exports.
// Reads only the central directory via Blob.slice (random access), then
// streams one entry through the browser's native DecompressionStream —
// the archive is never loaded into memory, so multi-GB exports work.

export interface ZipEntry {
  name: string;
  method: number;            // 0 = stored, 8 = deflate
  compressedSize: number;
  uncompressedSize: number;
  localHeaderOffset: number;
}

const SIG_EOCD = 0x06054b50, SIG_EOCD64 = 0x06064b50, SIG_LOC64 = 0x07064b50, SIG_CEN = 0x02014b50, SIG_LOC = 0x04034b50;

async function readBytes(blob: Blob, start: number, end: number): Promise<DataView> {
  const buf = await blob.slice(start, end).arrayBuffer();
  return new DataView(buf);
}

const u64 = (v: DataView, o: number) => Number(v.getBigUint64(o, true));

export async function listEntries(blob: Blob): Promise<ZipEntry[]> {
  const size = blob.size;
  const tailLen = Math.min(size, 65_557 + 20 + 56);
  const tail = await readBytes(blob, size - tailLen, size);
  let eocd = -1;
  for (let i = tail.byteLength - 22; i >= 0; i--) if (tail.getUint32(i, true) === SIG_EOCD) { eocd = i; break; }
  if (eocd < 0) throw new Error('Not a ZIP file (end of central directory not found).');
  let count = tail.getUint16(eocd + 10, true);
  let cdSize = tail.getUint32(eocd + 12, true);
  let cdOffset = tail.getUint32(eocd + 16, true);
  if (count === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) {
    const loc = eocd - 20;
    if (loc < 0 || tail.getUint32(loc, true) !== SIG_LOC64) throw new Error('ZIP64 locator missing.');
    const eocd64Offset = u64(tail, loc + 8);
    const e64 = await readBytes(blob, eocd64Offset, eocd64Offset + 56);
    if (e64.getUint32(0, true) !== SIG_EOCD64) throw new Error('ZIP64 end record missing.');
    count = u64(e64, 32);
    cdSize = u64(e64, 40);
    cdOffset = u64(e64, 48);
  }
  const cd = await readBytes(blob, cdOffset, cdOffset + cdSize);
  const entries: ZipEntry[] = [];
  const dec = new TextDecoder();
  let p = 0;
  for (let i = 0; i < count && p + 46 <= cd.byteLength; i++) {
    if (cd.getUint32(p, true) !== SIG_CEN) throw new Error('Corrupt central directory.');
    const method = cd.getUint16(p + 10, true);
    let csize = cd.getUint32(p + 20, true), usize = cd.getUint32(p + 24, true);
    const nameLen = cd.getUint16(p + 28, true), extraLen = cd.getUint16(p + 30, true), commentLen = cd.getUint16(p + 32, true);
    let offset = cd.getUint32(p + 42, true);
    const name = dec.decode(new Uint8Array(cd.buffer, cd.byteOffset + p + 46, nameLen));
    // ZIP64 extended information extra field (0x0001).
    let e = p + 46 + nameLen;
    const eEnd = e + extraLen;
    while (e + 4 <= eEnd) {
      const id = cd.getUint16(e, true), len = cd.getUint16(e + 2, true);
      if (id === 0x0001) {
        let q = e + 4;
        if (usize === 0xffffffff) { usize = u64(cd, q); q += 8; }
        if (csize === 0xffffffff) { csize = u64(cd, q); q += 8; }
        if (offset === 0xffffffff) { offset = u64(cd, q); q += 8; }
      }
      e += 4 + len;
    }
    entries.push({ name, method, compressedSize: csize, uncompressedSize: usize, localHeaderOffset: offset });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return entries;
}

export async function entryStream(blob: Blob, entry: ZipEntry): Promise<ReadableStream<Uint8Array>> {
  const lh = await readBytes(blob, entry.localHeaderOffset, entry.localHeaderOffset + 30);
  if (lh.getUint32(0, true) !== SIG_LOC) throw new Error('Corrupt local header.');
  const start = entry.localHeaderOffset + 30 + lh.getUint16(26, true) + lh.getUint16(28, true);
  const raw = blob.slice(start, start + entry.compressedSize).stream() as ReadableStream<Uint8Array>;
  if (entry.method === 0) return raw;
  if (entry.method === 8) return raw.pipeThrough(new DecompressionStream('deflate-raw') as unknown as ReadableWritablePair<Uint8Array, Uint8Array>);
  throw new Error(`Unsupported ZIP compression method ${entry.method}.`);
}

/** The main export XML: largest .xml under apple_health_export/ that isn't the CDA file. */
export function findExportXML(entries: ZipEntry[]): ZipEntry | undefined {
  return entries
    .filter((e) => e.name.toLowerCase().endsWith('.xml') && !e.name.toLowerCase().includes('cda') && !e.name.includes('__MACOSX'))
    .sort((a, b) => b.uncompressedSize - a.uncompressedSize)[0];
}

/** ECG recordings are separate CSV files: electrocardiograms/ecg_YYYY-MM-DD*.csv. */
export function ecgDays(entries: ZipEntry[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const e of entries) {
    const m = /electrocardiograms\/ecg_(\d{4}-\d{2}-\d{2})/i.exec(e.name);
    if (m) out.set(m[1], (out.get(m[1]) ?? 0) + 1);
  }
  return out;
}
