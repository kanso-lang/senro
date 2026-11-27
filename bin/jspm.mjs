// `senro js install` and `senro js check`, run from an app's directory: the
// app's JavaScript dependencies, managed as jspm-rails manages a Rails app's.
//
// The app's modules live in `javascript/`, and `javascript/application.js` is
// the entry. Install traces the entry, and every other module there, with
// jspm's generator. It downloads each module the trace reaches from
// ga.jspm.io, with the source maps they name, into `vendor/javascript/`, and
// writes the import map to `importmap.json` with the list of modules a page
// loads at once. senro's page script carries that map to the browser, so a
// deployed app needs neither Node nor jspm.io.
//
// An app's own stylesheets live in `stylesheets/`, and one may import a
// package's stylesheet by its name, `@import "bootstrap/dist/css/bootstrap.min.css";`.
// Install downloads each such file from ga.jspm.io, with the source map,
// fonts and images it names, into `vendor/javascript/`, and the map's
// `stylesheets` holds the URL it came from. senro rewrites the import to the
// vendored copy as it serves the stylesheet.
//
// Check traces and downloads again and writes nothing. It fails when an
// install would change `importmap.json`, or when a file under
// `vendor/javascript/` is missing, differs from what jspm.io serves, or is
// one the trace no longer reaches.
//
// Versions: the previous `importmap.json` locks every package it names, as
// jspm's lockfile does. A package's stylesheet takes the version its
// JavaScript has in the map, or the one the map's `stylesheets` held. A package npm installed at the top of
// `package-lock.json` takes the version npm chose, so Dependabot's bumps
// reach the map. The generator itself is resolved from the app's own
// `node_modules`, so the app pins its version like any other dependency.
import { createRequire } from "node:module";
import {
  existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const CDN = "https://ga.jspm.io/";
const LOCAL = "javascript";
const SHEETS = "stylesheets";
const ENTRY = "javascript/application.js";
const MAP = "importmap.json";
const VENDOR = "vendor/javascript";
const PACKAGE = /^https:\/\/ga\.jspm\.io\/npm:((?:@[^/]+\/)?[^@/]+)@([^/]+)\//;
const SOURCE_MAP = /\/\/# sourceMappingURL=(\S+\.map)\s*$/;
const CSS_SOURCE_MAP = /\/\*#\s*sourceMappingURL=(\S+?)\s*\*\/\s*$/;
const CSS_IMPORT = /@import\s+(?:url\(\s*)?["']([^"']+)["']/g;
const CSS_URL = /url\(\s*["']?([^"')]+?)["']?\s*\)/g;

const root = process.cwd();
const rootUrl = pathToFileURL(`${root}/`);

const report = (status, message) =>
  console.log(`${status.padStart(12)}  ${message}`);

const refused = (message) => {
  console.error(`senro js: ${message}`);
  process.exit(1);
};

// Where a jspm.io module is kept in the app. `npm:` becomes `npm/`, since a
// colon cannot be part of a file name on every system. senro serves the
// directory at the same path, and rewrites the map's URLs to match.
const vendored = (url) =>
  join(VENDOR, url.slice("https://".length).replace("/npm:", "/npm/"));

// Every module under javascript/, named as importmap-rails names them: its
// path without the extension, and a directory's name for its index.js.
const files = (dir, kind = /\.m?js$/) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const path = join(dir, e.name);
    if (e.isDirectory()) return files(path, kind);
    return kind.test(e.name) ? [path] : [];
  });

const named = (path) => {
  const name = relative(LOCAL, path).replace(/\.m?js$/, "");
  return name.endsWith("/index") ? name.slice(0, -"/index".length) : name;
};

// A path in the map as the browser asks for it: a module of the app's under
// /javascript/, and a jspm.io module by its URL, as the lockfile keeps it.
const served = (target) => {
  const url = new URL(target, rootUrl);
  if (url.protocol !== "file:") return url.href;
  return `/${relative(root, fileURLToPath(url)).split("\\").join("/")}`;
};

// A specifier that is a URL or a path is one too; a bare name stays a name.
const urlLike = (s) => /^(\.{0,2}\/|[a-z]+:)/.test(s);

const each = (specifiers, convert) =>
  Object.fromEntries(Object.entries(specifiers ?? {})
    .map(([k, v]) => [urlLike(k) ? convert(k) : k, convert(v)]));

const sorted = (object) =>
  Object.fromEntries(Object.entries(object).sort(([a], [b]) => (a < b ? -1 : 1)));

const json = (path) => JSON.parse(readFileSync(join(root, path), "utf8"));

// The packages npm installed. A package at the top of node_modules is the
// version the app asked for; one nested under another is a second version
// that a dependent's range wanted instead.
const installed = () => {
  if (!existsSync(join(root, "package-lock.json"))) return [];
  const packages = json("package-lock.json").packages ?? {};
  return Object.entries(packages)
    .filter(([path]) => path !== "")
    .map(([path, p]) => ({
      name: path.split("node_modules/").pop(),
      top: path.split("node_modules/").length === 2,
      version: p.version,
    }));
};

const generator = async () => {
  let path;
  try {
    path = createRequire(rootUrl).resolve("@jspm/generator");
  } catch {
    refused("the generator is not installed here. Run: npm install --save-dev @jspm/generator");
  }
  return (await import(pathToFileURL(path).href)).Generator;
};

const traced = async () => {
  if (!existsSync(join(root, ENTRY))) refused(`there is no ${ENTRY} to trace`);
  const packages = installed();
  const resolutions = Object.fromEntries(
    packages.filter((p) => p.top).map((p) => [p.name, p.version]));
  const pins = Object.fromEntries(files(LOCAL).map((f) => [named(f), f]));
  for (const name of Object.keys(pins)) {
    if (name in resolutions) {
      refused(`${pins[name]} has the name of the package ${name}; rename one of them`);
    }
  }
  // The previous map's jspm.io modules, keyed by specifier, so the trace
  // keeps the versions it already holds.
  const locked = {};
  let lockedSheets = {};
  if (existsSync(join(root, MAP))) {
    const previous = json(MAP);
    lockedSheets = previous.stylesheets ?? {};
    for (const specifiers of [previous.imports, ...Object.values(previous.scopes ?? {})]) {
      for (const [k, v] of Object.entries(specifiers ?? {})) {
        if (v.startsWith(CDN)) locked[k] = v;
      }
    }
  }
  const local = Object.fromEntries(
    Object.entries(pins).map(([name, f]) => [name, pathToFileURL(join(root, f)).href]));
  const Generator = await generator();
  const g = new Generator({
    baseUrl: rootUrl,
    mapUrl: rootUrl,
    combineSubpaths: true,
    defaultProvider: "jspm.io",
    env: ["browser", "module", "production"],
    flattenScopes: true,
    inputMap: { imports: { ...locked, ...local } },
    inputPins: false,
    resolutions,
  });
  const names = ["application", ...Object.keys(pins).filter((n) => n !== "application").sort()];
  const { staticDeps, dynamicDeps } = await g.link(names);
  const map = g.getMap();
  const scopes = Object.fromEntries(
    Object.entries(map.scopes ?? {}).map(([scope, s]) => [served(scope), sorted(each(s, served))]));
  const preload = staticDeps.map(served).sort();
  const reached = [...staticDeps, ...dynamicDeps].map(served).filter((u) => u.startsWith(CDN));
  const styles = stylesheets(resolutions, reached, lockedSheets);
  return {
    packages,
    map: {
      imports: sorted(each(map.imports, served)),
      ...(Object.keys(scopes).length > 0 ? { scopes: sorted(scopes) } : {}),
      preload,
      ...(Object.keys(styles).length > 0 ? { stylesheets: sorted(styles) } : {}),
    },
    cdn: [...new Set([...reached, ...Object.values(styles)])].sort(),
  };
};

// A package's name and the path inside it: `bootstrap/dist/css/x.css` and
// `@fontsource/inter/index.css`.
const split = (spec) => {
  const parts = spec.split("/");
  const n = spec.startsWith("@") ? 2 : 1;
  return [parts.slice(0, n).join("/"), parts.slice(n).join("/")];
};

// The packages' stylesheets the app's own stylesheets import by name, each
// with the URL jspm.io serves it from.
const stylesheets = (resolutions, reached, lockedSheets) => {
  if (!existsSync(join(root, SHEETS))) return {};
  const used = new Map();
  for (const url of reached) {
    const m = url.match(PACKAGE);
    if (m) used.set(m[1], m[2]);
  }
  const styles = {};
  for (const file of files(SHEETS, /\.css$/).sort()) {
    for (const [, spec] of readFileSync(file, "utf8").matchAll(CSS_IMPORT)) {
      if (urlLike(spec) || spec in styles) continue;
      const [name, path] = split(spec);
      if (path === "") {
        refused(`${file} imports ${spec}; name the stylesheet inside the package, as bootstrap/dist/css/bootstrap.min.css`);
      }
      const was = lockedSheets[spec]?.match(PACKAGE);
      const version = resolutions[name] ?? used.get(name) ?? was?.[2];
      if (!version) {
        refused(`${file} imports ${spec}, and neither package-lock.json nor the import map has ${name}. Run: npm install ${name}`);
      }
      styles[spec] = `${CDN}npm:${name}@${version}/${path}`;
    }
  }
  return styles;
};

// Each module the trace reached, and each source map a module names, keyed
// by where it is kept.
const fetched = async (urls) => {
  const got = new Map();
  const fetchOne = async (url, optional = false) => {
    if (got.has(vendored(url))) return;
    const r = await fetch(url);
    // A source map is for a debugger, and jspm.io does not keep every one
    // a file names (Bootstrap's stylesheet names one it lacks), so one that
    // is not there is left out rather than stopping the install.
    if (!r.ok && optional) return;
    if (!r.ok) refused(`${url} answered ${r.status}`);
    const body = Buffer.from(await r.arrayBuffer());
    got.set(vendored(url), body);
    if (url.endsWith(".map")) return;
    const text = body.toString("utf8");
    const named = text.match(url.endsWith(".css") ? CSS_SOURCE_MAP : SOURCE_MAP);
    if (named) await fetchOne(new URL(named[1], url).href, true);
    if (url.endsWith(".css")) {
      for (const ref of referenced(text)) await fetchOne(new URL(ref, url).href);
    }
  };
  for (const url of urls) await fetchOne(url);
  return got;
};

// What a vendored stylesheet names beside it: the stylesheets it imports and
// the fonts and images its url()s point at, without a query or a fragment,
// which the server does not read.
const referenced = (css) => {
  const refs = [...css.matchAll(CSS_IMPORT), ...css.matchAll(CSS_URL)].map((m) => m[1]);
  return [...new Set(refs
    .filter((r) => !/^(data:|#|[a-z]+:)/.test(r) && !r.startsWith("/"))
    .map((r) => r.replace(/[?#].*$/, "")))];
};

const text = (map) => `${JSON.stringify(map, null, 2)}\n`;

const kept = () =>
  existsSync(VENDOR)
    ? readdirSync(VENDOR, { recursive: true, withFileTypes: true })
      .filter((e) => e.isFile())
      .map((e) => join(e.parentPath ?? e.path, e.name))
    : [];

// npm installs a second version of a package when its dependents' ranges do
// not meet. An import map holds one, so the map uses the top-level version
// everywhere, and says so.
const warned = (packages, cdn) => {
  const used = new Map();
  for (const url of cdn) {
    const m = url.match(PACKAGE);
    if (m) used.set(m[1], m[2]);
  }
  for (const [name, version] of [...used].sort()) {
    const nested = packages.filter((p) => !p.top && p.name === name).map((p) => p.version);
    const all = [...new Set([...nested, version])].sort();
    if (all.length > 1) {
      report("warn", `${name}: package-lock.json has ${all.join(" and ")}, and the import map uses ${version} everywhere`);
    }
  }
};

const install = async () => {
  const { packages, map, cdn } = await traced();
  const got = await fetched(cdn);
  rmSync(VENDOR, { recursive: true, force: true });
  for (const [path, body] of got) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, body);
  }
  writeFileSync(MAP, text(map));
  report("traced", ENTRY);
  const sheets = cdn.filter((u) => u.endsWith(".css")).length;
  const counted = (n, one) => `${n} ${one}${n === 1 ? "" : "s"}`;
  const kinds = [counted(cdn.length - sheets, "module"), ...(sheets > 0 ? [counted(sheets, "stylesheet")] : [])];
  report("vendored", `${kinds.join(" and ")} from ga.jspm.io`);
  report("wrote", MAP);
  warned(packages, cdn);
};

const check = async () => {
  const { map, cdn } = await traced();
  const got = await fetched(cdn);
  let clean = true;
  const was = existsSync(MAP) ? readFileSync(MAP, "utf8") : null;
  if (was !== text(map)) {
    report("stale", MAP);
    clean = false;
  }
  for (const [path, body] of got) {
    if (!existsSync(path)) {
      report("missing", path);
      clean = false;
    } else if (!readFileSync(path).equals(body)) {
      report("changed", path);
      clean = false;
    }
  }
  for (const path of kept().sort()) {
    if (!got.has(path)) {
      report("stray", path);
      clean = false;
    }
  }
  if (clean) {
    report("ok", "nothing to install");
  } else {
    report("run", "senro js install");
    process.exit(1);
  }
};

const [command] = process.argv.slice(2);
if (command === "install") await install();
else if (command === "check") await check();
else refused("usage: senro js install | senro js check");
