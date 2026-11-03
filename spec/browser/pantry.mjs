// The pantry driven in a real browser with senro's page script loaded: add,
// count up and down, rename and remove, each answered in place, and a second
// visitor's page that follows the first's changes. The page
// marks its window first; a page that reloaded would lose the mark. Prints
// what a visitor sees after each step, for spec.sh to compare with
// spec/browser/pantry.out. Run as:
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

await page.goto(`http://127.0.0.1:${port}/`);
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
await row(1).locator("button.minus").click();
await page.waitForLoadState("networkidle");
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
await browser.close();
