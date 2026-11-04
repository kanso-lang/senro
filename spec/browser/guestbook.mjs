// The guestbook signed in a real browser, with senro's page script and the
// guestbook's browser module loaded.
// The page marks its window before signing; a page that reloaded would lose
// the mark. Then the visitor removes her own entry, and is refused when she
// asks to remove someone else's. Prints what a visitor sees, for spec.sh to
// compare with spec/browser/guestbook.out. Run as:
//
//   node spec/browser/guestbook.mjs <port> <browser>
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const playwright = require("playwright");
const [port, kind] = process.argv.slice(2);
const browser = await playwright[kind].launch();
const page = await browser.newPage();
const said = [];
page.on("pageerror", (e) => said.push(`page error: ${e.message}`));

// Bob signs first, in a browser context of his own.
const bob = await (await browser.newContext()).newPage();
await bob.goto(`http://127.0.0.1:${port}/`);
await bob.fill("input[name=name]", "Bob");
await bob.fill("textarea[name=message]", "from Bob");
await bob.click("button");
await bob.waitForSelector("p.flash");

// Each page the script fetches after the first comes as data, which the
// guestbook's views compiled for the browser render, once the module has
// loaded.
const fetched = [];
page.on("response", (r) => {
  const asked = r.request();
  if (asked.resourceType() !== "fetch" || new URL(r.url()).pathname !== "/") return;
  fetched.push(r.headers()["senro-view"] ? "data" : "html");
});
await page.goto(`http://127.0.0.1:${port}/`);
await page.waitForSelector("html.senro-ready", { state: "attached" });
await page.evaluate(() => { window.senroMark = "kept"; });
await page.fill("input[name=name]", "Ada");
await page.fill("textarea[name=message]", "signed without a reload");
await page.click("button");
await page.waitForSelector("p.flash");

const seen = await page.evaluate(() => ({
  mark: window.senroMark || "lost",
  path: location.pathname,
  title: document.title,
  flash: document.querySelector("p.flash").textContent,
  first: document.querySelector("ol.entries li p.message").textContent,
  who: document.querySelector("ol.entries li p.who").textContent,
  name: document.querySelector("input[name=name]").value,
  message: document.querySelector("textarea[name=message]").value,
}));
console.log(`window mark: ${seen.mark}`);
console.log(`path: ${seen.path}`);
console.log(`title: ${seen.title}`);
console.log(`flash: ${seen.flash}`);
console.log(`newest entry: ${seen.first}, by ${seen.who}`);
console.log(`name field: ${seen.name}`);
console.log(`message field: "${seen.message}"`);

// Signing signed Ada in under her name. Her entries have a remove button,
// and nobody else's do; the button is a server action, so the click posts to
// the server, which removes the entry only because the policy says she may.
const buttons = await page.evaluate(() =>
  [...document.querySelectorAll("ol.entries li")]
    .filter((li) => li.querySelector("button.remove"))
    .every((li) => li.querySelector("p.who").textContent === "Ada"));
console.log(`remove buttons only on Ada's entries: ${buttons}`);
const before = await page.evaluate(() => document.querySelectorAll("ol.entries li").length);
await page.locator("ol.entries li").first().locator("button.remove").click();
await page.waitForFunction(
  (n) => document.querySelectorAll("ol.entries li").length === n - 1, before);
const newest = await page.evaluate(() => {
  const li = document.querySelector("ol.entries li");
  return `${li.querySelector("p.message").textContent}, by ${li.querySelector("p.who").textContent}`;
});
console.log(`newest entry after Ada removes hers: ${newest}`);

// Bob's own page shows his remove button, and with it his entry's id. Ada
// asks the server to remove that entry; her session says she is Ada, and the
// policy refuses.
await bob.reload();
const his = await bob.evaluate(() =>
  document.querySelector("ol.entries li [data-component=removal]").dataset.state);
const asked = await page.evaluate(async (state) => {
  const r = await fetch("/senro/act/removal", {
    method: "POST", headers: { "senro-page": "spec" }, body: `removed\n${state}`,
  });
  return r.status;
}, his);
console.log(`Ada asking to remove Bob's entry: ${asked}`);
console.log(`Ada's page fetched / as: ${fetched.join(", ")}`);
for (const line of said) console.log(line);
await browser.close();
