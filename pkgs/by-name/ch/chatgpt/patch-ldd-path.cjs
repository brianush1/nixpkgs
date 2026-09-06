// Patch one packed file without changing which native modules remain unpacked.
// Preserve the other file payloads and refresh the changed file's ASAR integrity.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const archive = process.argv[2],
  ldd = process.argv[3];
if (!archive || !ldd || !fs.existsSync(ldd))
  throw Error("Archive and existing ldd path required");
const original = fs.readFileSync(archive);
const index = JSON.parse(original.subarray(16, 16 + original.readUInt32LE(12)));
const dataStart = 8 + original.readUInt32LE(4);
const entries = [];
function walk(tree, prefix = "") {
  for (const [name, entry] of Object.entries(tree.files ?? {})) {
    const nameWithPath = prefix + name;
    if (entry.files) walk(entry, nameWithPath + "/");
    else if (entry.offset !== undefined)
      entries.push({ name: nameWithPath, entry, offset: Number(entry.offset) });
  }
}
walk(index);
entries.sort((a, b) => a.offset - b.offset);
const target =
  "node_modules/@parcel/watcher/node_modules/detect-libc/lib/filesystem.js";
const hit = entries.find((x) => x.name === target);
if (!hit) throw Error("Expected detect-libc dependency missing");
const before = original
  .subarray(dataStart + hit.offset, dataStart + hit.offset + hit.entry.size)
  .toString();
const needle = "'/usr/bin/ldd'";
if (before.split(needle).length !== 2)
  throw Error("Expected exactly one standard ldd path");
const patched = Buffer.from(before.replace(needle, JSON.stringify(ldd)));
let offset = 0;
for (const item of entries) {
  item.bytes =
    item === hit
      ? patched
      : original.subarray(
          dataStart + item.offset,
          dataStart + item.offset + item.entry.size,
        );
  item.entry.offset = String(offset);
  item.entry.size = item.bytes.length;
  offset += item.bytes.length;
  if (item === hit && item.entry.integrity) {
    const blockSize = item.entry.integrity.blockSize;
    const blocks = [];
    for (let i = 0; i < patched.length; i += blockSize)
      blocks.push(
        crypto
          .createHash("sha256")
          .update(patched.subarray(i, i + blockSize))
          .digest("hex"),
      );
    item.entry.integrity = {
      algorithm: "SHA256",
      hash: crypto.createHash("sha256").update(patched).digest("hex"),
      blockSize,
      blocks,
    };
  }
}
const json = Buffer.from(JSON.stringify(index));
const header = Buffer.alloc(8 + Math.ceil(json.length / 4) * 4);
header.writeUInt32LE(header.length - 4, 0);
header.writeUInt32LE(json.length, 4);
json.copy(header, 8);
const size = Buffer.alloc(8);
size.writeUInt32LE(4, 0);
size.writeUInt32LE(header.length, 4);
const tmp = archive + ".patched";
const out = fs.openSync(tmp, "w", fs.statSync(archive).mode);
fs.writeSync(out, size);
fs.writeSync(out, header);
for (const item of entries) fs.writeSync(out, item.bytes);
fs.closeSync(out);
fs.renameSync(tmp, archive);
const verify = fs.readFileSync(archive);
const start = 8 + verify.readUInt32LE(4);
for (const item of entries) {
  const bytes = verify.subarray(
    start + Number(item.entry.offset),
    start + Number(item.entry.offset) + item.entry.size,
  );
  if (!bytes.equals(item.bytes))
    throw Error("Repacked file differs: " + item.name);
}
const testDir = archive + ".detect-libc-test";
fs.mkdirSync(testDir);
for (const item of entries.filter((x) =>
  x.name.startsWith(
    "node_modules/@parcel/watcher/node_modules/detect-libc/lib/",
  ),
)) {
  fs.writeFileSync(path.join(testDir, path.basename(item.name)), item.bytes);
}
// This must detect glibc without calling the API that crashes in Electron's worker.
const saved = process.report.getReport;
process.report.getReport = () => {
  throw Error("Unexpected report fallback");
};
const family = require(path.join(testDir, "detect-libc.js")).familySync();
process.report.getReport = saved;
if (family !== "glibc") throw Error("Unexpected libc family " + family);
fs.rmSync(testDir, { recursive: true });
console.log(
  JSON.stringify({
    patched: target,
    ldd,
    family,
    verifiedArchiveEntries: entries.length,
  }),
);
