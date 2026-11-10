// The fuzzer for wire: random values, packed here by the reference and
// there by wire/wire.kso, and each side made to read the other's bytes.
//
//   node spec/wire/fuzz.mjs <kanso> <cases> [seed]
//
// For every value the kanso checker (spec/wire/checked) is handed the
// reference's bytes and the value as JSON. It answers whether the bytes read
// back as that value, and its own bytes for the value, which the reference
// reads back here. A value is a boolean, an integer, a float, a string, a
// list or a map of those; none is not among them, because JSON has no way
// to say it that kanso reads as none, and spec/runs/wire covers it.
//
// Prints the number of cases and stops at the first that disagrees, with
// the seed, so a failure can be run again.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { decimal, pack, unpack } from "./reference.mjs";

const [kanso, wanted, seeded] = process.argv.slice(2);
const cases = Number(wanted);
let state = BigInt(seeded || 20261110);

// xorshift64*, so a run is a function of its seed on every machine.
const next = () => {
  state ^= state >> 12n;
  state ^= (state << 25n) & 0xffffffffffffffffn;
  state ^= state >> 27n;
  return (state * 0x2545f4914f6cdd1dn) & 0xffffffffffffffffn;
};
const below = (n) => Number(next() % BigInt(n));
const pick = (xs) => xs[below(xs.length)];

// Integers at every edge a count has: one byte, the tag's limit, each power
// of 128, and the ends of 64 bits.
const edges = [0n, 1n, 127n, 128n, 16383n, 16384n, 2n ** 31n, 2n ** 53n + 1n,
  2n ** 62n, 2n ** 63n - 1n, -1n, -2n, -128n, -129n, -(2n ** 63n)];
const integer = () => {
  if (below(4) === 0) return pick(edges);
  const wide = BigInt.asIntN(below(63) + 1, next());
  return wide;
};

const floats = [0.5, -0.5, 1.5, 1e21, 1e-7, 5e-324, 1.7976931348623157e308,
  2 ** 53, 0.1, 1 / 3, -123456.789, 1e100];
const float = () => {
  if (below(3) === 0) return pick(floats);
  const view = new DataView(new ArrayBuffer(8));
  view.setBigUint64(0, next());
  const x = view.getFloat64(0);
  return Number.isFinite(x) && x !== 0 ? x : 0.25;
};

// Code points from every length utf-8 has, with the ends of each range, a
// zero byte, quotes and backslashes, the byte order mark a careless decoder
// drops, and nothing from the surrogates.
const points = [0, 9, 10, 13, 34, 92, 127, 128, 0x7ff, 0x800, 0xd7ff, 0xe000,
  0xfeff, 0xfffd, 0xffff, 0x10000, 0x1f30d, 0x10ffff];
const point = () => {
  if (below(3) === 0) return pick(points);
  const p = below(pick([128, 0x800, 0x10000, 0x110000]));
  return p >= 0xd800 && p <= 0xdfff ? 0x41 : p;
};
// A string of an exact length in bytes, since that is what the format
// counts: the lengths either side of the tag's limit, of a count's second
// byte and of its third, filled with random code points and then with `a`.
const sizes = [0, 1, 2, 5, 20, 62, 63, 64, 65, 126, 127, 128, 129, 300];
const long = [16383, 16384, 16385];
const utf8Length = (s) => new TextEncoder().encode(s).length;
const string = () => {
  const size = below(400) === 0 ? pick(long) : pick(sizes);
  let s = "";
  let used = 0;
  for (let tries = 0; tries < 40 && used < size; tries++) {
    const c = String.fromCodePoint(point());
    const n = utf8Length(c);
    if (used + n <= size) {
      s += c;
      used += n;
    }
  }
  return s + "a".repeat(size - used);
};

const value = (depth) => {
  const kind = below(depth > 3 ? 4 : 6);
  if (kind === 0) return below(2) === 0;
  if (kind === 1) return integer();
  if (kind === 2) return float();
  if (kind === 3) return string();
  const n = pick([0, 1, 2, 3, 8]);
  if (kind === 4) return Array.from({ length: n }, () => value(depth + 1));
  const m = new Map();
  for (let i = 0; i < n; i++) m.set(string(), value(depth + 1));
  return m;
};

// JSON by hand: an integer is written whole, whatever its size, and a float
// always with a point or an exponent.
const json = (v) => {
  if (typeof v === "bigint") return v.toString();
  if (typeof v === "number") return decimal(v);
  if (typeof v === "string" || typeof v === "boolean") return JSON.stringify(v);
  if (Array.isArray(v)) return "[" + v.map(json).join(",") + "]";
  return "{" + [...v].map(([k, x]) => JSON.stringify(k) + ":" + json(x)).join(",") + "}";
};

const same = (a, b) => {
  if (typeof a !== typeof b) return false;
  if (a === null || typeof a !== "object") return Object.is(a, b);
  if (Array.isArray(a)) {
    return Array.isArray(b) && a.length === b.length && a.every((x, i) => same(x, b[i]));
  }
  if (!(b instanceof Map) || a.size !== b.size) return false;
  for (const [k, x] of a) if (!b.has(k) || !same(x, b.get(k))) return false;
  return true;
};

const work = fs.mkdtempSync(path.join(os.tmpdir(), "senro-wire-"));
const here = path.dirname(new URL(import.meta.url).pathname);
let done = 0;
while (done < cases) {
  const batch = [];
  for (let i = 0; i < 2000 && done + batch.length < cases; i++) batch.push(value(0));
  const lines = batch.map((v) => Buffer.from(pack(v)).toString("base64") + "\t" + json(v));
  const file = path.join(work, "cases");
  fs.writeFileSync(file, lines.join("\n") + "\n");
  const out = execFileSync(kanso, ["run", "."], {
    cwd: path.join(here, "checked"),
    env: { ...process.env, SENRO_WIRE_CASES: file },
    maxBuffer: 1 << 28,
  }).toString().split("\n");
  batch.forEach((v, i) => {
    const [read, spelt] = (out[i] || "").split("\t");
    const back = unpack(Uint8Array.from(Buffer.from(spelt || "", "base64")));
    if (read !== "read" || back === undefined || !same(v, back)) {
      console.error(`wire disagrees with its reference at case ${done + i}`);
      console.error(`  value   ${json(v)}`);
      console.error(`  kanso   ${out[i]}`);
      console.error(`  read as ${back === undefined ? "nothing" : json(back)}`);
      console.error(`  seed    ${seeded || 20261110}`);
      process.exit(1);
    }
  });
  done += batch.length;
}
fs.rmSync(work, { recursive: true });
console.log(`wire agrees with its reference on ${done} values`);
