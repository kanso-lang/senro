// The pantry driven in a real browser with senro's page script loaded: add,
// count up and down, rename and remove, each answered in place; a component
// whose clicks run in the browser; and a second visitor's page that follows
// the first's changes. The page marks its window first; a page that reloaded
// would lose the mark. Prints what a visitor sees after each step, for
// spec.sh to compare with spec/browser/pantry.out. Run as:
//
//   node spec/browser/pantry.mjs <port> <browser> [screenshot directory]
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const playwright = require("playwright");
const [port, kind, shots] = process.argv.slice(2);
const browser = await playwright[kind].launch();
const page = await browser.newPage({ viewport: { width: 640, height: 640 } });
page.on("pageerror", (e) => console.log(`page error: ${e.message}`));
let shot = 0;

// Each action waits for the answer it causes: the count of rows, a row's
// text, or the rename field, as the step expects.
const settled = async (check) => {
  await page.waitForFunction(check, null, { timeout: 5000 });
};

const said = async (step) => {
  const seen = await page.evaluate(() => ({
    mark: window.senroMark || "lost",
    lede: document.querySelector(".lede").textContent,
    rows: [...document.querySelectorAll(".items li")].map((li) => {
      const name = li.querySelector(".name, input[name=name]");
      const text = name.value === undefined ? name.textContent : name.value;
      return `${text}: ${li.querySelector(".count").textContent}`;
    }),
  }));
  console.log(`${step}: ${seen.lede} [${seen.rows.join(", ")}] mark ${seen.mark}`);
  if (shots) await page.screenshot({ path: `${shots}/${++shot}-${step.replace(/ /g, "-")}.png` });
};

const rows = () => document.querySelectorAll(".items li").length;
const row = (n) => page.locator(".items li").nth(n);

// Each page the script fetches comes as data once the module has loaded,
// and the pantry's views compiled for the browser render it.
const fetched = [];
page.on("response", (r) => {
  if (r.request().resourceType() !== "fetch" || r.status() !== 200) return;
  const path = new URL(r.url()).pathname;
  if (path.startsWith("/senro/")) return;
  fetched.push(r.headers()["senro-view"] ? "data" : "html");
});
await page.goto(`http://127.0.0.1:${port}/`);
await page.waitForSelector("html.senro-ready", { state: "attached" });
await page.evaluate(() => { window.senroMark = "kept"; });

// Whatever an earlier run left on the shelf goes first, through the page.
while (await page.evaluate(rows) > 0) {
  const before = await page.evaluate(rows);
  await row(0).locator("button.delete").click();
  await settled(`document.querySelectorAll(".items li").length < ${before}`);
}
await said("emptied");

for (const name of ["Rice", "Tea", "Lentils"]) {
  const before = await page.evaluate(rows);
  await page.fill(".add input[name=name]", name);
  await page.press(".add input[name=name]", "Enter");
  await settled(`document.querySelectorAll(".items li").length > ${before}`);
}
await said("added three");
console.log(`add field after Enter: "${await page.inputValue(".add input[name=name]")}"`);

for (let n = 1; n <= 3; n++) {
  await row(0).locator("button.plus").click();
  await settled(`document.querySelector(".items li .count").textContent == "${n}"`);
}
await row(1).locator("button.plus").click();
await settled(`document.querySelectorAll(".items li .count")[1].textContent == "1"`);
await row(1).locator("button.minus").click();
await settled(`document.querySelectorAll(".items li .count")[1].textContent == "0"`);
// A count at nought stays there, so nothing on the page changes to wait for.
// The page keeps a stream open for live changes, so the network is never
// idle either; the wait is for the answer to the request itself.
const floored = page.waitForResponse((r) => r.request().method() === "POST");
await row(1).locator("button.minus").click();
await floored;
await said("counted");

await row(1).locator("a.name").click();
await settled(`document.activeElement && document.activeElement.name == "name"`);
await said("renaming");
await page.fill(".rename input[name=name]", "Green tea");
await page.click(".rename button");
await settled(`!document.querySelector(".rename")`);
await said("renamed");

await row(2).locator("button.delete").click();
await settled(`document.querySelectorAll(".items li").length == 2`);
await said("removed");
console.log(`path: ${await page.evaluate(() => location.pathname)}`);

// Two visits in flight at once. Another visitor's change makes this page
// refresh itself, and that refresh is held back here; meanwhile this visitor
// opens a rename. The rename's page is the later visit, so when the held
// refresh answers last, its page is dropped and the rename stays open.
const bystander = await (await browser.newContext()).newPage();
await bystander.goto(`http://127.0.0.1:${port}/`);
let release;
const held = new Promise((r) => { release = r; });
let holding;
const caught = new Promise((r) => { holding = r; });
await page.route(`http://127.0.0.1:${port}/`, async (route) => {
  holding();
  await held;
  await route.continue();
}, { times: 1 });
await bystander.locator(".items li").nth(1).locator("button.minus").click();
await caught;
await row(0).locator("a.name").click();
await settled(`document.activeElement && document.activeElement.name == "name"`);
const late = page.waitForResponse(`http://127.0.0.1:${port}/`);
release();
await late;
await page.waitForTimeout(200);
const open = await page.evaluate(() => !!document.querySelector(".rename"));
console.log(`a rename opened while a refresh was in flight stays open: ${open}`);
await page.click(".rename a");
await settled(`!document.querySelector(".rename")`);
await bystander.context().close();

// The planner is a component. Its clicks run in the browser, in the app's
// module built for wasm, and send the server nothing. A page the server sends
// later, after a change to the shelf, leaves its count where the clicks put
// it. Each click waits for the one before, since an action reads the state
// the last one left.
await page.waitForFunction(
  () => document.documentElement.classList.contains("senro-ready"),
);
let asked = 0;
const counting = (r) => { if (!r.url().endsWith(".wasm")) asked++; };
page.on("request", counting);
for (const [button, after] of [["plus", 4], ["plus", 5], ["minus", 4]]) {
  await page.click(`.planner button.${button}`);
  await settled(`document.querySelector(".planner .count").textContent == "${after}"`);
}
page.off("request", counting);
const planned = () => page.textContent(".planner .count");
console.log(`planner: ${await planned()} after three clicks, ${asked} requests`);
await row(0).locator("button.plus").click();
await settled(`document.querySelector(".items li .count").textContent == "4"`);
console.log(`planner after the shelf changed: ${await planned()}`);

// The browser module is downloaded once per change to it: asked for again
// with the ETag it came with, the server answers 304 and no body. A module
// that is not there is a 404, and the server goes on serving.
const module = `http://127.0.0.1:${port}/senro/app.wasm`;
const tag = (await fetch(module)).headers.get("etag");
const again = await fetch(module, { headers: { "if-none-match": tag } });
console.log(`the browser module asked for again with its ETag: ${again.status}`);
const nope = await fetch(`http://127.0.0.1:${port}/senro/nope.wasm`);
console.log(`a module that is not there: ${nope.status}`);

// The staple star is a component whose action writes to the database, so it
// runs on the server: the click posts the star's state, and the answer is
// the star drawn in its next state.
await row(0).locator("button.staple").click();
await settled(`document.querySelector(".items li button.staple.on")`);
const stars = await page.evaluate(() =>
  [...document.querySelectorAll(".items li button.staple")]
    .map((b) => b.textContent).join(" "));
console.log(`staples after starring the first: ${stars}`);

// What a page may ask the server to do: only an action a template binds, on
// a component the app serves, from senro's own script.
const act = async (component, body, headers) => {
  const r = await fetch(`http://127.0.0.1:${port}/senro/act/${component}`, {
    method: "POST", headers, body,
  });
  return r.status;
};
const ours = { "senro-page": "spec" };
const first = await page.evaluate(() =>
  document.querySelector(".items li [data-component=staple]").dataset.state);
console.log(`act without the page's header: ${await act("staple", `toggled\n${first}`, {})}`);
console.log(`act naming an action no template binds: ${await act("staple", `staple?\n${first}`, ours)}`);
console.log(`act with a state that is not JSON: ${await act("staple", "toggled\n{", ours)}`);
console.log(`act on a component the app does not serve: ${await act("planner", `more\n3`, ours)}`);

// A second visitor, in a browser context of its own, has the shelf open. A
// change the first makes reaches the second's page with no click there.
const other = await (await browser.newContext()).newPage();
await other.goto(`http://127.0.0.1:${port}/`);
await other.evaluate(() => { window.senroMark = "kept"; });
await other.waitForTimeout(300);
await row(1).locator("button.plus").click();
await other.waitForFunction(
  () => document.querySelectorAll(".items li .count")[1].textContent == "1",
  null, { timeout: 5000 },
);
const seen = await other.evaluate(() => ({
  mark: window.senroMark || "lost",
  count: document.querySelectorAll(".items li .count")[1].textContent,
}));
console.log(`the other visitor sees green tea at ${seen.count}, mark ${seen.mark}`);
const asData = fetched.length > 0 && fetched.every((k) => k === "data");
console.log(`every page the shelf fetched came as data: ${asData}`);
await browser.close();
