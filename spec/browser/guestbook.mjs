// The guestbook signed in a real browser, with senro's page script loaded.
// The page marks its window before signing; a page that reloaded would lose
// the mark. Prints what a visitor sees after signing, for spec.sh to compare
// with spec/browser/guestbook.out. Run as:
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

await page.goto(`http://127.0.0.1:${port}/`);
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
for (const line of said) console.log(line);
await browser.close();
