// The guestbook signed in a real browser, with senro's page script and the
// guestbook's browser module loaded. Each visitor makes an account and signs
// with it. The page marks its window before signing; a page that reloaded
// would lose the mark. Then the visitor removes her own entry, and is refused
// when she asks to remove someone else's. Prints what a visitor sees, for
// spec.sh to compare with spec/browser/guestbook.out. Run as:
//
//   node spec/browser/guestbook.mjs <port> <browser>
import { createRequire } from "node:module";
import { statSync, utimesSync } from "node:fs";

const require = createRequire(import.meta.url);
const playwright = require("playwright");
const [port, kind] = process.argv.slice(2);
const browser = await playwright[kind].launch();
const page = await browser.newPage();
const said = [];
page.on("pageerror", (e) => said.push(`page error: ${e.message}`));

const at = (path) => `http://127.0.0.1:${port}${path}`;

// Makes an account from the front page's link, and waits for the book. The
// interpreted run finds the account the native run made, and signs in.
async function joined(p, name, password) {
  await p.goto(at("/"));
  await p.click("a[href='/accounts/new']");
  await p.waitForSelector("input[type=password]");
  await p.fill("input[name=name]", name);
  await p.fill("input[name=password]", password);
  await p.click("form button");
  await p.waitForSelector("form.out, p.problem");
  if (await p.$("form.out")) return;
  await p.goto(at("/session/new"));
  await p.fill("input[name=name]", name);
  await p.fill("input[name=password]", password);
  await p.click("form button");
  await p.waitForSelector("form.out");
}

// Bob signs first, in a browser context of his own.
const bob = await (await browser.newContext()).newPage();
await joined(bob, "Bob", "bobs password");
await bob.fill("textarea[name=message]", "from Bob");
await bob.click("form.sign button");
await bob.waitForSelector("p.flash");

// A visitor who is not signed in is offered the door and no form.
const visitor = await (await browser.newContext()).newPage();
await visitor.goto(at("/"));
const door = await visitor.evaluate(() => ({
  links: [...document.querySelectorAll("nav.door a")].map((a) => a.textContent).join(", "),
  form: document.querySelector("form.sign") ? "shown" : "none",
}));
console.log(`a visitor sees: ${door.links}; sign form: ${door.form}`);

// Signing in with the wrong password is refused with one message, whether
// or not the name has an account.
async function refused(name) {
  await visitor.goto(at("/session/new"));
  await visitor.fill("input[name=name]", name);
  await visitor.fill("input[name=password]", "not the password");
  await visitor.click("form button");
  await visitor.waitForSelector("p.problem");
  return visitor.evaluate(() => document.querySelector("p.problem").textContent);
}
console.log(`Bob, a wrong password: ${await refused("Bob")}`);
console.log(`a name with no account: ${await refused("Nobody")}`);

// A name already taken and a short password are both turned back.
await visitor.goto(at("/accounts/new"));
await visitor.fill("input[name=name]", "Bob");
await visitor.fill("input[name=password]", "short");
await visitor.click("form button");
await visitor.waitForSelector("p.problem");
const taken = await visitor.evaluate(() =>
  [...document.querySelectorAll("p.problem")].map((p) => p.textContent).join(" "));
console.log(`taking Bob's name with a short password: ${taken}`);

// Each page the script fetches after the first comes as data, which the
// guestbook's views compiled for the browser render, once the module has
// loaded.
const fetched = [];
page.on("response", (r) => {
  const asked = r.request();
  if (asked.resourceType() !== "fetch" || new URL(r.url()).pathname !== "/") return;
  fetched.push(r.headers()["senro-view"] ? "data" : "html");
});
await joined(page, "Ada", "adas password");
await page.waitForSelector("html.senro-ready", { state: "attached" });
await page.evaluate(() => { window.senroMark = "kept"; });

// A message of spaces passes the browser's required check and fails the
// model's rule, so the form comes back with the problem.
await page.fill("textarea[name=message]", "   ");
await page.click("form.sign button");
await page.waitForSelector("p.problem");
const turned = await page.evaluate(() => document.querySelector("p.problem").textContent);
console.log(`a message of spaces: ${turned}`);

await page.fill("textarea[name=message]", "signed without a reload");
await page.click("form.sign button");
await page.waitForFunction(() =>
  document.querySelector("p.flash")?.textContent === "Thank you for signing.");

const seen = await page.evaluate(() => ({
  mark: window.senroMark || "lost",
  path: location.pathname,
  title: document.title,
  flash: document.querySelector("p.flash").textContent,
  first: document.querySelector("ol.entries li p.message").textContent,
  who: document.querySelector("ol.entries li p.who").textContent,
  signed: document.querySelector("form.out span").textContent,
  message: document.querySelector("textarea[name=message]").value,
}));
console.log(`window mark: ${seen.mark}`);
console.log(`path: ${seen.path}`);
console.log(`title: ${seen.title}`);
console.log(`flash: ${seen.flash}`);
console.log(`newest entry: ${seen.first}, by ${seen.who}`);
console.log(`signed in: ${seen.signed}`);
console.log(`message field: "${seen.message}"`);

// Ada's entries have a remove button,
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

// Signing out leaves the door where the form was.
await page.click("form.out button");
await page.waitForSelector("nav.door");
const out = await page.evaluate(() => document.querySelector("p.flash").textContent);
console.log(`after signing out: ${out}`);

// The page's modules come from the browser's Cache Storage once they have
// been fetched, so loading the page again asks the server for neither.
const modules = [];
page.on("request", (q) => {
  const path = new URL(q.url()).pathname;
  if (path.endsWith(".wasm")) modules.push(path);
});
await page.reload();
await page.waitForSelector("html.senro-ready", { state: "attached" });
console.log(`modules fetched by a second load: ${modules.length}`);

// A deploy moves the app module's modification time, which is its version.
// The page's next request learns of it, the page loads itself again, and
// only the module that changed is fetched.
const module = "examples/guestbook/public/senro/app.wasm";
const was = statSync(module);
utimesSync(module, was.atime, new Date(was.mtimeMs + 60000));
await page.evaluate(() => { window.senroMark = "before the deploy"; });
await page.click("a[href='/session/new']");
await page.waitForFunction(() => window.senroMark === undefined);
await page.waitForSelector("html.senro-ready", { state: "attached" });
console.log(`after a deploy, fetched: ${modules.join(", ")}`);
console.log(`Ada's page fetched / as: ${fetched.join(", ")}`);
for (const line of said) console.log(line);
await browser.close();
