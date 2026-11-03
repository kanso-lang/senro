// An app's browser module run the way the page script runs it: linked
// against the kanso runtime built for wasm32, with the event in SENRO_EVENT.
// Prints what the module printed. Run as:
//
//   node spec/browser/module.mjs <runtime.wasm> <app.wasm> <event>
import fs from "node:fs";

const [runtimePath, appPath, event] = process.argv.slice(2);
class Exit {}
const out = [];
let memory = null;
const bytes = () => new Uint8Array(memory.buffer);
const view = () => new DataView(memory.buffer);
const env = new TextEncoder().encode(`SENRO_EVENT=${event}\0`);
const calls = {
  fd_write(fd, iovs, n, written) {
    let total = 0;
    for (let k = 0; k < n; k++) {
      const at = view().getUint32(iovs + k * 8, true);
      const len = view().getUint32(iovs + k * 8 + 4, true);
      const piece = bytes().slice(at, at + len);
      if (fd === 1) out.push(piece);
      else process.stderr.write(piece);
      total += len;
    }
    view().setUint32(written, total, true);
    return 0;
  },
  environ_sizes_get(count, size) {
    view().setUint32(count, 1, true);
    view().setUint32(size, env.length, true);
    return 0;
  },
  environ_get(at, buf) {
    view().setUint32(at, buf, true);
    bytes().set(env, buf);
    return 0;
  },
  args_sizes_get(count, size) {
    view().setUint32(count, 0, true);
    view().setUint32(size, 0, true);
    return 0;
  },
  fd_fdstat_get(fd, stat) {
    bytes().fill(0, stat, stat + 24);
    return 0;
  },
  fd_prestat_get: () => 8,
  proc_exit() {
    throw new Exit();
  },
};
const wasi = new Proxy(calls, { get: (t, name) => t[name] || (() => 0) });
const runtime = await WebAssembly.instantiate(fs.readFileSync(runtimePath), {
  wasi_snapshot_preview1: wasi,
});
const rt = runtime.instance.exports;
memory = rt.memory;
const app = new WebAssembly.Module(fs.readFileSync(appPath));
const link = new DataView(WebAssembly.Module.customSections(app, "kanso.link")[0]);
const table = rt.__indirect_function_table;
const fixed = (n) => new WebAssembly.Global({ value: "i32", mutable: false }, n);
const imports = {
  memory: rt.memory,
  __indirect_function_table: table,
  __memory_base: fixed(rt.malloc(link.getUint32(0, true))),
  __table_base: fixed(table.grow(link.getUint32(4, true))),
};
for (const imp of WebAssembly.Module.imports(app)) {
  if (!(imp.name in imports)) imports[imp.name] = rt[imp.name];
}
await WebAssembly.instantiate(app, { env: imports });
try {
  rt._start();
} catch (e) {
  if (!(e instanceof Exit)) throw e;
}
process.stdout.write(Buffer.concat(out.map((b) => Buffer.from(b))));
