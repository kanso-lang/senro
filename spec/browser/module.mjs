// An app's browser module run the way the page script runs it: by the page
// script's own runner, the text spec/browser/runner prints, against the
// kanso runtime built for wasm32, with the event in SENRO_EVENT and, for a
// page, its bytes as the one file the module can open, /senro/page. Prints
// what the module printed. Run as:
//
//   node spec/browser/module.mjs <runner.js> <runtime.wasm> <app.wasm> <event> [page file]
import fs from "node:fs";

const [runnerPath, runtimePath, appPath, event, pagePath] = process.argv.slice(2);
const source = fs.readFileSync(runnerPath, "utf8");
const run = new Function(`${source}\nreturn module_run;`)();
const runtime = new WebAssembly.Module(fs.readFileSync(runtimePath));
const app = new WebAssembly.Module(fs.readFileSync(appPath));
const page = pagePath ? new Uint8Array(fs.readFileSync(pagePath)) : null;
const told = (piece) => process.stderr.write(piece);
process.stdout.write(await run(runtime, app, event, page, told));
