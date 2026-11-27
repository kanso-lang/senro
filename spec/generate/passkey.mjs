// The generated app's passkeys in a real browser. Chromium's virtual
// authenticator, added through the DevTools protocol, stands in for a
// phone or a laptop's: it makes a resident ES256 key and verifies its user.
// A visitor makes an account with a passkey, confirms the address through
// the link the app mailed to <outbox>, signs in with the passkey, and,
// with its cookies gone, signs in again, which moves the key's signature count. A passkey
// the app does not know is refused. WebAuthn takes a host name and not an
// address, so the page is visited at localhost. Prints what the visitor
// sees, for spec.sh to compare with spec/generate/passkey.out. Each door
// also offers a password to a visitor who asks for one, and the account
// page adds a passkey, removes one and shows a new password. Run as:
//
//   node spec/generate/passkey.mjs <port> <outbox>
import { createRequire } from "node:module";
import { readdirSync, readFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const [port, outbox] = process.argv.slice(2);
const at = (path) => `http://localhost:${port}${path}`;
const browser = await chromium.launch();
const said = [];

async function visitor() {
  const page = await (await browser.newContext()).newPage();
  page.on("pageerror", (e) => said.push(`page error: ${e.message}`));
  const cdp = await page.context().newCDPSession(page);
  await cdp.send("WebAuthn.enable");
  const { authenticatorId } = await cdp.send("WebAuthn.addVirtualAuthenticator", {
    options: {
      protocol: "ctap2",
      transport: "internal",
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
    },
  });
  return { page, cdp, authenticatorId };
}

const text = (p, sel) => p.evaluate((s) => document.querySelector(s)?.textContent.trim() ?? "nothing", sel);

function mails() {
  return readdirSync(outbox).sort((a, b) => parseInt(a) - parseInt(b));
}

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

const email = `passkey-${Date.now()}@example.test`;
const { page, cdp, authenticatorId } = await visitor();

const asks = (p) => p.evaluate(() =>
  [...document.querySelectorAll("form input:not([type=hidden])")].map((i) => i.name).join(", "));

// Each door offers a password, chosen by the app, to a visitor who follows
// "Use a password instead".
async function insteadOf(door) {
  await page.goto(at(door));
  await page.click("text=Use a password instead");
  await page.waitForURL((u) => u.search === "?with=password");
  console.log(`${door}, using a password instead, asks for: ${await asks(page) || "nothing"}`);
}
await insteadOf("/registration/new");
await insteadOf("/session/new");

await page.goto(at("/registration/new"));
console.log(`the sign-up form asks for: ${await asks(page)}`);
await page.fill("input[name=email]", email);
const since = mails().length;
await page.click("button[data-passkey=create]");
await page.waitForSelector("p.notice");
console.log(`making the account: ${await text(page, "h1")}; ${await text(page, "p.notice")}`);
const { credentials } = await cdp.send("WebAuthn.getCredentials", { authenticatorId });
console.log(`the authenticator holds: ${credentials.length} key, resident: ${credentials[0]?.isResidentCredential}`);

await page.goto(at("/session/new"));
await page.click("button[data-passkey=get]");
await page.waitForSelector("p.problem:not(:empty)");
console.log(`signing in before confirming: ${await text(page, "p.problem")}`);

const mail = await mailTo(email, since);
const link = at(new URL(mail.match(/^(http:\/\/\S+\/edit)\r$/m)[1]).pathname);
await page.goto(link);
await page.click("form button");
await page.waitForSelector("p.notice");
console.log(`confirming: ${await text(page, "p.notice")}`);

async function signedIn() {
  await page.goto(at("/session/new"));
  await page.click("button[data-passkey=get]");
  await page.waitForFunction(() => location.pathname !== "/session/new" ||
    document.querySelector("p.problem:not(:empty)"));
  return `${new URL(page.url()).pathname} ${await text(page, "p.notice")}`;
}
console.log(`signing in with the passkey: ${await signedIn()}`);
const counted = (await cdp.send("WebAuthn.getCredentials", { authenticatorId })).credentials[0].signCount;
await page.goto(at("/notes"));
console.log(`a page that asks for a sign-in: ${new URL(page.url()).pathname}`);
// A browser that forgets its cookies is signed out, and signs in again.
await page.context().clearCookies();
console.log(`signing in again: ${await signedIn()}`);
const after = (await cdp.send("WebAuthn.getCredentials", { authenticatorId })).credentials[0].signCount;
console.log(`its count rose: ${after > counted}`);

// The account's page lists its passkeys. One is added from this device and
// one removed, and a new password is shown once without ending the sign-in.
const listed = () => page.evaluate(() =>
  document.querySelectorAll("form[action^='/credentials/']").length);
await page.goto(at("/account"));
const named = (await text(page, "p.text-secondary")) === `Signed in as ${email}`;
console.log(`the account page: ${await text(page, "h1")}; names the visitor: ${named}; passkeys: ${await listed()}`);
await page.click("button[data-passkey=create]");
await page.waitForSelector("p.notice");
console.log(`adding a passkey: ${await text(page, "p.notice")}; passkeys: ${await listed()}`);
await page.click("form[action^='/credentials/'] button");
await page.waitForFunction(() => document.querySelector("p.notice")?.textContent.includes("removed"));
console.log(`removing one: ${await text(page, "p.notice")}; passkeys: ${await listed()}`);
await page.click("form[action='/account'] button");
await page.waitForSelector("code.password");
const chosen = await text(page, "code.password");
console.log(`a new password: ${await text(page, "h1")}, ${chosen.length > 12 ? "shown" : "missing"}`);
await page.goto(at("/account"));
console.log(`still signed in after it: ${new URL(page.url()).pathname}`);

// Another visitor's authenticator holds a key for this site that the app
// never kept, as a key made against another copy of the app would be.
const stranger = await visitor();
await stranger.page.goto(at("/session/new"));
await stranger.cdp.send("WebAuthn.addCredential", {
  authenticatorId: stranger.authenticatorId,
  credential: {
    credentialId: Buffer.from("not-a-kept-key").toString("base64"),
    isResidentCredential: true,
    rpId: "localhost",
    privateKey: (await import("node:crypto")).generateKeyPairSync("ec", { namedCurve: "P-256" })
      .privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"),
    userHandle: Buffer.from("stranger").toString("base64"),
    signCount: 0,
  },
});
await stranger.page.click("button[data-passkey=get]");
await stranger.page.waitForSelector("p.problem:not(:empty)");
console.log(`a key the app never kept: ${await text(stranger.page, "p.problem")}`);

for (const line of said) console.log(line);
await browser.close();
