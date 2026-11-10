// senro's wire format, written a second time from the description at the top
// of wire/wire.kso and from nothing else, so that the fuzzer has something
// independent to hold the kanso to. Integers are BigInt and floats are
// Number, so the two never blur; a map is a Map, which keeps its order.

const utf8 = new TextEncoder();
// ignoreBOM, or a string that begins with U+FEFF loses it on the way back:
// the fuzzer's case 62,397 was that, the reference's fault and not wire's.
const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });

const count = (out, n) => {
  let left = BigInt(n);
  while (left >= 128n) {
    out.push(Number(left & 127n) + 128);
    left >>= 7n;
  }
  out.push(Number(left));
};

const bytes = (out, piece) => {
  for (const b of piece) out.push(b);
};

const put = (out, v) => {
  if (v === null) return out.push(192);
  if (v === false) return out.push(193);
  if (v === true) return out.push(194);
  if (typeof v === "bigint") {
    if (v >= 0n && v < 128n) return out.push(Number(v));
    if (v > 0n) return (out.push(195), count(out, v));
    return (out.push(196), count(out, -(v + 1n)));
  }
  if (typeof v === "number") {
    const spelt = utf8.encode(decimal(v));
    out.push(197);
    count(out, spelt.length);
    return bytes(out, spelt);
  }
  if (typeof v === "string") {
    const spelt = utf8.encode(v);
    if (spelt.length < 64) out.push(128 + spelt.length);
    else (out.push(198), count(out, spelt.length));
    return bytes(out, spelt);
  }
  if (Array.isArray(v)) {
    out.push(199);
    count(out, v.length);
    for (const x of v) put(out, x);
    return;
  }
  out.push(200);
  count(out, v.size);
  for (const [k, x] of v) (put(out, k), put(out, x));
};

// A float as decimal text that reads back as the same float and that no
// reader takes for an integer.
export const decimal = (x) => {
  const s = String(x);
  return /[.e]/.test(s) || !Number.isFinite(x) ? s : s + ".0";
};

export const pack = (v) => {
  const out = [];
  put(out, v);
  return Uint8Array.from(out);
};

class Lost extends Error {}

const read = (bs, at) => {
  const number = () => {
    let n = 0n;
    let shift = 0n;
    for (;;) {
      if (at.p >= bs.length) throw new Lost();
      const b = bs[at.p++];
      n += BigInt(b & 127) << shift;
      if (b < 128) return n;
      shift += 7n;
    }
  };
  const run = (n) => {
    const len = Number(n);
    if (at.p + len > bs.length) throw new Lost();
    const piece = bs.subarray(at.p, at.p + len);
    at.p += len;
    return piece;
  };
  if (at.p >= bs.length) throw new Lost();
  const tag = bs[at.p++];
  if (tag < 128) return BigInt(tag);
  if (tag < 192) return text.decode(run(tag - 128));
  if (tag === 192) return null;
  if (tag === 193) return false;
  if (tag === 194) return true;
  if (tag === 195) return number();
  if (tag === 196) return -number() - 1n;
  if (tag === 197) return Number(text.decode(run(number())));
  if (tag === 198) return text.decode(run(number()));
  if (tag === 199) {
    const n = number();
    const xs = [];
    for (let i = 0n; i < n; i++) xs.push(read(bs, at));
    return xs;
  }
  if (tag === 200) {
    const n = number();
    const m = new Map();
    for (let i = 0n; i < n; i++) {
      const k = read(bs, at);
      m.set(k, read(bs, at));
    }
    return m;
  }
  throw new Lost();
};

// The value the bytes hold, or undefined when they are not one value and
// nothing else.
export const unpack = (bs) => {
  const at = { p: 0 };
  try {
    const v = read(bs, at);
    return at.p === bs.length ? v : undefined;
  } catch (e) {
    return undefined;
  }
};
