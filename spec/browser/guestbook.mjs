// The guestbook signed in a real browser, with senro's page script and the
// guestbook's browser module loaded. Each visitor makes an account and signs
// with it. The page marks its window before signing; a page that reloaded
// would lose the mark. A visitor who asks to be kept signed in keeps a cookie
// that outlives the browser through every later write to her session, until
// she signs out. Then the visitor removes her own entry, and is refused
// when she asks to remove someone else's. Nobody chooses a password: the
// guestbook shows the one it chose when an account is made, reset or
// changed, and the visitor signs in with what it showed. A visitor who has
// lost her password asks for a link, reads it in the mail the app wrote to
// <outbox>, and is given a new one, and later changes it from her account
// page. Prints what a visitor sees, for spec.sh to compare with
// spec/browser/guestbook.out. Run as:
//
//   node spec/browser/guestbook.mjs <port> <browser> <outbox>
import { createRequire } from "node:module";
import { readdirSync, readFileSync, statSync, utimesSync } from "node:fs";

const require = createRequire(import.meta.url);
const playwright = require("playwright");
const [port, kind, outbox] = process.argv.slice(2);
const browser = await playwright[kind].launch();
const page = await browser.newPage();
const said = [];
page.on("pageerror", (e) => said.push(`page error: ${e.message}`));

const at = (path) => `http://127.0.0.1:${port}${path}`;

// The password the page shows, the only time it is shown.
const shown = (p) => p.evaluate(() => document.querySelector("code.password").textContent);

// Makes an account from the front page's link and answers its password, and
// whether the account is new. The database outlives a run, so a later run
// finds the account an earlier one made, whose password it never saw; it
// asks for a reset link and is given a new password, which also confirms
// the address.
async function made(p, name) {
  const email = `${name.toLowerCase()}@guestbook.test`;
  await p.goto(at("/"));
  await p.click("a[href='/registration/new']");
  await p.waitForSelector("input[name=email]");
  await p.fill("input[name=name]", name);
  await p.fill("input[name=email]", email);
  const since = mails().length;
  await p.click("form button");
  await p.waitForSelector("code.password, p.problem");
  if (await p.$("code.password")) return { password: await shown(p), fresh: true, since };
  return { password: await renewed(p, email), fresh: false, since };
}

async function renewed(p, email) {
  await p.goto(at("/resets/new"));
  await p.fill("input[name=email]", email);
  const since = mails().length;
  await p.click("form button");
  await p.waitForFunction(() => document.querySelector("p.notice"));
  await p.goto(linkIn(await mailTo(email, since)));
  await p.click("form button");
  await p.waitForSelector("code.password");
  return shown(p);
}

// Makes an account, confirms its address through the link the guestbook
// mails, and signs in with the password it showed, ticking "Keep me signed
// in" when `remember` says to.
async function joined(p, name, remember = false) {
  const email = `${name.toLowerCase()}@guestbook.test`;
  const { password, fresh, since } = await made(p, name);
  if (fresh) {
    await p.goto(linkIn(await mailTo(email, since)));
    await p.click("form button");
    await p.waitForFunction(() =>
      document.querySelector("p.notice")?.textContent.startsWith("Your address"));
  }
  await p.goto(at("/session/new"));
  await p.fill("input[name=name]", name);
  await p.fill("input[name=password]", password);
  if (remember) await p.check("input[name=remember]");
  await p.click("form button");
  await p.waitForSelector("form.out");
  return password;
}

// A name no run has used, for a visitor whose account must be new.
const fresh = (name) => `${name}${Date.now().toString(36)}`;

// Who the session cookie of the context `p` is in names as its viewer. The
// cookie is the session as base64 JSON, a dot, and its signature.
async function viewerIn(p) {
  const [c] = await p.context().cookies(at("/"));
  const held = JSON.parse(Buffer.from(c.value.split(".")[0], "base64").toString());
  return held.viewer ?? "nobody";
}

// How long the browser keeps the session cookie of the context `p` is in.
async function cookieLife(p) {
  const [c] = await p.context().cookies(at("/"));
  if (c.expires === -1) return "until the browser closes";
  return `${Math.round((c.expires - Date.now() / 1000) / 86400)} days`;
}

// The newest mail to `to` among those written after the first `since`. The
// guestbook queues its mail and a worker sends it a moment later, so this
// waits for one to arrive.
async function mailTo(to, since) {
  for (let tries = 0; tries < 300; tries++) {
    for (const f of mails().slice(since).reverse()) {
      const m = readFileSync(`${outbox}/${f}`, "utf8");
      if (m.includes(`\r\nTo: ${to}\r\n`)) return m;
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error(`no mail to ${to}`);
}

function linkIn(mail) {
  return mail.match(/^(http:\/\/\S+\/edit)\r$/m)[1];
}

// Bob signs first, in a browser context of his own.
const bob = await (await browser.newContext()).newPage();
await joined(bob, "Bob");
await bob.fill("textarea[name=message]", "from Bob");
await bob.click("form.sign button");
await bob.waitForSelector("p.notice");

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

// A name and an address already taken are both turned back, and the form
// asks for no password.
await visitor.goto(at("/registration/new"));
const askedFor = await visitor.evaluate(() =>
  document.querySelector("input[type=password]") ? "a password" : "no password");
await visitor.fill("input[name=name]", "Bob");
await visitor.fill("input[name=email]", "BOB@guestbook.test");
await visitor.click("form button");
await visitor.waitForSelector("p.problem");
const taken = await visitor.evaluate(() =>
  [...document.querySelectorAll("p.problem")].map((p) => p.textContent).join(" "));
console.log(`the sign-up form asks for ${askedFor}`);
console.log(`taking Bob's name and address: ${taken}`);

// Di makes an account and never follows the link that would confirm it.
// The page that answers shows her password and says to save it. Her
// password is answered by a request to confirm first, and the link is sent
// again. Her account must be new, so each run names her afresh.
const di = await (await browser.newContext()).newPage();
const diName = fresh("Di");
const diMail = `${diName.toLowerCase()}@guestbook.test`;
const { password: diPassword, since: beforeDi } = await made(di, diName);
const told = await di.evaluate(() => document.querySelector("p.notice").textContent);
console.log(`Di's new account: ${told}`);
console.log(`its password: ${/^[A-Za-z0-9.!#+=?@-]+$/.test(diPassword) ? "shown" : diPassword}`);
await mailTo(diMail, beforeDi);
const sentToDi = mails().length;
await di.goto(at("/session/new"));
await di.fill("input[name=name]", diName);
await di.fill("input[name=password]", diPassword);
await di.click("form button");
await di.waitForSelector("p.problem");
const unconfirmed = await di.evaluate(() => document.querySelector("p.problem").textContent);
await mailTo(diMail, sentToDi);
console.log(`Di, not yet confirmed: ${unconfirmed}; mail sent: ${mails().length - sentToDi}`);

// Cy has lost her password. She asks for a link from the sign-in page, and
// the guestbook answers the same whether or not the address has an account.
// The link in the mail opens a button, and pressing it gives her a new
// password, which she signs in with; the link works only once. A run that
// finds her account already made resets it all the same.
const cy = await (await browser.newContext()).newPage();
await cy.goto(at("/registration/new"));
await cy.fill("input[name=name]", "Cy");
await cy.fill("input[name=email]", "cy@guestbook.test");
const beforeCy = mails().length;
await cy.click("form button");
await cy.waitForSelector("code.password, p.problem");
if (await cy.$("code.password")) await mailTo("cy@guestbook.test", beforeCy);
await cy.goto(at("/session/new"));
await cy.click("a[href='/resets/new']");
const sentBefore = mails().length;
await cy.fill("input[name=email]", "nobody@guestbook.test");
await cy.click("form button");
await cy.waitForFunction(() => document.querySelector("p.notice"));
const nobody = await cy.evaluate(() => document.querySelector("p.notice").textContent);
console.log(`a link for an address with no account: ${nobody}`);
await cy.goto(at("/resets/new"));
await cy.fill("input[name=email]", "cy@guestbook.test");
await cy.click("form button");
await cy.waitForFunction(() => document.querySelector("p.notice"));
// The worker sends mail in the order it was queued, so once Cy's has come,
// any for the address with no account would have come before it.
const mail = await mailTo("cy@guestbook.test", sentBefore);
const header = (name) => mail.match(new RegExp(`^${name}: (.*)\r$`, "m"))[1];
console.log(`mail to ${header("To")}: ${header("Subject")}; mail sent: ${mails().length - sentBefore}`);
const link = mail.match(/^(http:\/\/\S+\/edit)\r$/m)[1];
await cy.goto(link);
const offered = await cy.evaluate(() => document.querySelector("form button").textContent);
console.log(`the link opens: ${offered}`);
await cy.click("form button");
await cy.waitForSelector("code.password");
const cyPassword = await shown(cy);
console.log(`after pressing it: ${await cy.evaluate(() => document.querySelector("p.notice").textContent)}`);
await cy.goto(at("/session/new"));
await cy.fill("input[name=name]", "Cy");
await cy.fill("input[name=password]", cyPassword);
await cy.click("form button");
await cy.waitForSelector("form.out");
console.log(`signing in with the new password: ${await cy.evaluate(() => document.querySelector("form.out span").textContent)}`);
await cy.goto(link);
await cy.waitForSelector("p.notice");
console.log(`the link again: ${await cy.evaluate(() => document.querySelector("p.notice").textContent)}`);

// Signed in, Cy changes her password from her account page. A wrong current
// password is refused; the right one gives her a new password and leaves
// her signed in, so a page that asks for a sign-in still opens; and the old
// one, tried again, no longer counts as her current password.
async function changed(current) {
  await cy.goto(at("/"));
  await cy.click("a[href='/password/edit']");
  await cy.waitForSelector("input[name=current]");
  await cy.fill("input[name=current]", current);
  await cy.click("form button");
  await cy.waitForSelector("code.password, p.problem");
  if (await cy.$("p.problem")) return cy.evaluate(() => document.querySelector("p.problem").textContent);
  const again = await shown(cy);
  return again === current ? "the same password" : "a new password, shown once";
}
console.log(`changing with a wrong password: ${await changed("not hers")}`);
console.log(`changing with hers: ${await changed(cyPassword)}`);
await cy.goto(at("/password/edit"));
console.log(`and then her account page: ${new URL(cy.url()).pathname}`);
// The page counts her sign-ins and, from the second on, says when and from
// where the one before this came. The database outlives a run, so whether
// this is her first depends on the runs before: the line prints as agreed
// when it reads one way or the other, and as it reads otherwise.
const arrivals = await cy.evaluate(() => document.querySelector("p.seen")?.textContent ?? "nothing");
const first = /^You have signed in once\.$/;
const later = /^You have signed in \d+ times\. The time before this one was \d{4}-\d\d-\d\d \d\d:\d\d UTC, from 127\.0\.0\.1\.$/;
const agreed = first.test(arrivals) || later.test(arrivals);
console.log(`her sign-ins: ${agreed ? "counted, and the one before named" : arrivals}`);
console.log(`the old one again: ${await changed(cyPassword)}`);

// Fay's account locks after three wrong passwords in a row. Each is answered
// as any wrong password is, and the third mails her a link to unlock it.
// Her right password is then told the account is locked, and the link
// unlocks it. Signing in is limited to ten tries in three minutes from one
// address, and these four bring this run's to ten. Her account must be new,
// so each run names her afresh.
const fay = await (await browser.newContext()).newPage();
const fayName = fresh("Fay");
const fayMail = `${fayName.toLowerCase()}@guestbook.test`;
const { password: fayPassword, since: beforeJoining } = await made(fay, fayName);
await fay.goto(linkIn(await mailTo(fayMail, beforeJoining)));
await fay.click("form button");
await fay.waitForSelector("p.notice");
async function tried(password) {
  await fay.goto(at("/session/new"));
  await fay.fill("input[name=name]", fayName);
  await fay.fill("input[name=password]", password);
  await fay.click("form button");
  await fay.waitForSelector("p.problem");
  return fay.evaluate(() => document.querySelector("p.problem").textContent);
}
const beforeFay = mails().length;
const wrongs = [];
for (const guess of ["fay1", "fay2", "fay3"]) wrongs.push(await tried(guess));
const unlocking = await mailTo(fayMail, beforeFay);
console.log(`Fay, three wrong passwords: ${[...new Set(wrongs)].join(" ")}; mail sent: ${mails().length - beforeFay}`);
console.log(`and then her own: ${await tried(fayPassword)}`);
console.log(`mail to Fay: ${unlocking.match(/^Subject: (.*)\r$/m)[1]}`);
await fay.goto(linkIn(unlocking));
await fay.click("form button");
await fay.waitForSelector("p.notice");
console.log(`following its link: ${await fay.evaluate(() => document.querySelector("p.notice").textContent)}`);
await fay.goto(linkIn(unlocking));
await fay.waitForSelector("p.notice");
console.log(`the link again: ${await fay.evaluate(() => document.querySelector("p.notice").textContent)}`);

// The mail the app has written so far, oldest first.
function mails() {
  return readdirSync(outbox).sort((a, b) => parseInt(a) - parseInt(b));
}

// Each page the script fetches after the first comes as data, which the
// guestbook's views compiled for the browser render, once the module has
// loaded. They are counted once Ada has signed in, since how she got there
// depends on whether an earlier run made her account.
await joined(page, "Ada", true);
const fetched = [];
page.on("response", (r) => {
  const asked = r.request();
  if (asked.resourceType() !== "fetch" || new URL(r.url()).pathname !== "/") return;
  fetched.push(r.headers()["senro-view"] ? "data" : "html");
});
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
  document.querySelector("p.notice")?.textContent === "Thank you for signing.");

const seen = await page.evaluate(() => ({
  mark: window.senroMark || "lost",
  path: location.pathname,
  title: document.title,
  notice: document.querySelector("p.notice").textContent,
  first: document.querySelector("ol.entries li p.message").textContent,
  who: document.querySelector("ol.entries li p.who").textContent,
  signed: document.querySelector("form.out span").textContent,
  message: document.querySelector("textarea[name=message]").value,
}));
console.log(`window mark: ${seen.mark}`);
console.log(`path: ${seen.path}`);
console.log(`title: ${seen.title}`);
console.log(`notice: ${seen.notice}`);
console.log(`newest entry: ${seen.first}, by ${seen.who}`);
console.log(`signed in: ${seen.signed}`);
console.log(`message field: "${seen.message}"`);

// Ada ticked "Keep me signed in", and the cookie keeps that through every
// later write to the session: the notice set when she signed, and the one
// cleared when the page showed it.
console.log(`Ada's cookie, kept: ${await cookieLife(page)}`);

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

// Ada signs again with a photo. The form is multipart, and the page script
// posts it as it is, file and all, without a reload. The entry shows the
// photo, which the server keeps under a key and serves back byte for byte.
// Then she removes the entry.
const png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";
await page.fill("textarea[name=message]", "with a photo");
await page.setInputFiles("input[name=photo]",
  { name: "ada.png", mimeType: "image/png", buffer: Buffer.from(png, "base64") });
await page.click("form.sign button");
await page.waitForFunction(() =>
  document.querySelector("ol.entries li p.message")?.textContent === "with a photo");
const photo = await page.evaluate(async (sent) => {
  const img = document.querySelector("ol.entries li img.photo");
  if (!img) return "no photo";
  const r = await fetch(img.src);
  const got = new Uint8Array(await r.arrayBuffer());
  const same = btoa(String.fromCharCode(...got)) === sent;
  return `${r.status} ${r.headers.get("content-type")}, ${same ? "as sent" : "changed"}`;
}, png);
console.log(`signed with a photo: ${photo}; window mark: ${await page.evaluate(() => window.senroMark || "lost")}`);
const pictured = await page.evaluate(() => document.querySelectorAll("ol.entries li").length);
await page.locator("ol.entries li").first().locator("button.remove").click();
await page.waitForFunction(
  (n) => document.querySelectorAll("ol.entries li").length === n - 1, pictured);

// Bob's own page shows his remove button, and with it his entry's id. Ada
// asks the server to remove that entry; her session says she is Ada, and the
// policy refuses.
await bob.reload();
const his = await bob.evaluate(() =>
  document.querySelector("ol.entries li [data-component=removal]").dataset.state);
const asked = await page.evaluate(async (state) => {
  const r = await fetch("/senro/act/removal", {
    method: "POST", headers: { "senro-page": "spec", "senro-from": "/" }, body: `removed\n${state}`,
  });
  return r.status;
}, his);
console.log(`Ada asking to remove Bob's entry: ${asked}`);

// Signing out leaves the door where the form was.
await page.click("form.out button");
await page.waitForSelector("nav.door");
const out = await page.evaluate(() => document.querySelector("p.notice").textContent);
console.log(`after signing out: ${out}`);
console.log(`and her cookie: ${await cookieLife(page)}`);

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

// Bob's password is set again through a reset link. The digest changes,
// and Bob's older session, still open in his browser, is signed out:
// the remove button on his own entry, a server action, finds nobody signed
// in and is refused, and the book, which asks for no sign-in, shows him the
// door.
const helper = await (await browser.newContext()).newPage();
await renewed(helper, "bob@guestbook.test");
const stale = await bob.evaluate(async (state) => {
  const r = await fetch("/senro/act/removal", {
    method: "POST", headers: { "senro-page": "spec", "senro-from": "/" }, body: `removed\n${state}`,
  });
  return r.status;
}, his);
console.log(`Bob's older session, removing his own entry after the reset: ${stale}`);
console.log(`and his cookie then names: ${await viewerIn(bob)}`);
await bob.goto(at("/"));
const bobNow = await bob.evaluate(() => document.querySelector("nav.door") ? "signed out" : "still signed in");
console.log(`and the book then sees him as: ${bobNow}`);
for (const line of said) console.log(line);
await browser.close();
