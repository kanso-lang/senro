// The generated app's Turnstile check in a real browser, with Cloudflare
// stood in for twice: the widget's script, which senro's page script loads
// from challenges.cloudflare.com, is answered with a stub that draws a
// token into the form, and the siteverify the app asks, which
// TURNSTILE_VERIFY points here, passes the token "person" and nothing else.
// A visitor whose token is refused is asked again with a fresh widget, and
// the sign-in form has none. Prints what the visitor sees, for spec.sh to
// compare with spec/generate/turnstile.out. Run as:
//
//   node spec/generate/turnstile.mjs <port> <verifier port>
import { createRequire } from "node:module";
import { createServer } from "node:http";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const [port, verifier] = process.argv.slice(2);
const at = (path) => `http://localhost:${port}${path}`;

const asked = [];
const siteverify = createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    const f = new URLSearchParams(body);
    asked.push(f.get("response"));
    const person = f.get("secret") === "the-secret" && f.get("response") === "person";
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ success: person, "error-codes": [] }));
  });
});
await new Promise((ok) => siteverify.listen(Number(verifier), "127.0.0.1", ok));

// The widget: a hidden field holding the token, as Cloudflare's widget puts
// one in its form. Drawing it again after a reset puts a fresh token there.
const stub = `
  const fields = new Map();
  window.drawn = 0;
  window.turnstile = {
    render(el, opts) {
      const f = document.createElement("input");
      f.type = "hidden";
      f.name = "cf-turnstile-response";
      f.value = "person";
      el.append(f);
      window.drawn++;
      window.keyed = opts.sitekey;
      fields.set(String(window.drawn), f);
      return String(window.drawn);
    },
    reset(id) {
      fields.get(id).value = "person";
      window.drawn++;
    },
  };
  window[new URL(document.currentScript.src).searchParams.get("onload")]();
`;

const browser = await chromium.launch();
const page = await (await browser.newContext()).newPage();
const said = [];
page.on("pageerror", (e) => said.push(`page error: ${e.message}`));
await page.route("https://challenges.cloudflare.com/**", (r) =>
  r.fulfill({ contentType: "text/javascript", body: stub }));

const text = (s) => page.evaluate((q) =>
  document.querySelector(q)?.textContent.trim() ?? "nothing", s);
const tokens = () => page.evaluate(() =>
  document.querySelectorAll("form [name=cf-turnstile-response]").length);

await page.goto(at("/registration/new?with=password"));
await page.waitForFunction(() => window.drawn > 0);
const key = await page.evaluate(() => window.keyed);
console.log(`the sign-up form draws the widget with the site key: ${key}; tokens: ${await tokens()}`);

// A token the check refuses, as one that has expired or was forged.
await page.fill("input[name=email]", `turnstile-${Date.now()}@example.test`);
await page.evaluate(() => {
  document.querySelector("[name=cf-turnstile-response]").value = "robot";
});
await page.click("form button");
await page.waitForSelector("p.problem:not(:empty)");
console.log(`with a refused token: ${await text("h1")}; ${await text("p.problem")}`);
const redrawn = await page.evaluate(() => window.drawn);
const fresh = await page.evaluate(() =>
  document.querySelector("[name=cf-turnstile-response]").value);
console.log(`the widget is drawn afresh: ${redrawn === 2}, its token: ${fresh}; tokens: ${await tokens()}`);

await page.click("form button");
await page.waitForSelector("code.password");
console.log(`sent again: ${await text("h1")}`);

await page.goto(at("/resets/new"));
await page.waitForFunction(() => document.querySelector("[name=cf-turnstile-response]"));
console.log(`the reset form carries a token: ${await tokens()}`);
await page.goto(at("/session/new?with=password"));
console.log(`the sign-in form carries one: ${await tokens()}`);
console.log(`siteverify was asked about: ${asked.join(", ")}`);

for (const line of said) console.log(line);
await browser.close();
siteverify.close();
