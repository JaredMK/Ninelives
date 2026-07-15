// Build the app's local web bundle (www/) from the ONE web codebase at the
// repo root. No game code is forked: this copies index.html + items.js +
// difficulty.js + tutorial.js verbatim and then patches EXACTLY TWO things
// for offline use:
//   1. the Google Fonts <link>s -> the bundled fonts/fonts.css (same faces),
//   2. the Google Analytics loader <script> -> removed (its inline config is
//      a documented no-op when gtag never loads).
// Everything else in the game is inline (data-URI art) or relative (items.js /
// difficulty.js), so the bundle is fully offline. Fails LOUDLY if a patch
// pattern is missing, so a game-side change can never silently ship an
// online-dependent bundle.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const appDir = dirname(dirname(fileURLToPath(import.meta.url)));
const repoDir = dirname(appDir);
const www = join(appDir, "www");

rmSync(www, { recursive: true, force: true });
mkdirSync(join(www, "fonts"), { recursive: true });
for (const f of ["index.html", "items.js", "difficulty.js", "tutorial.js"]) {
  cpSync(join(repoDir, f), join(www, f));
}
cpSync(join(appDir, "assets", "fonts"), join(www, "fonts"), { recursive: true });

let html = readFileSync(join(www, "index.html"), "utf8");
const mustPatch = (label, re, replacement) => {
  if (!re.test(html)) throw new Error("build-www: pattern not found for " + label + " — index.html changed; update this script");
  html = html.replace(re, replacement);
};

// 1. Fonts: swap the hosted Google Fonts links (plus their preconnects) for
//    the bundled stylesheet. One link replaces the first stylesheet; the
//    others are dropped.
mustPatch("fonts preconnect", /^<link rel="preconnect" href="https:\/\/fonts\.(googleapis|gstatic)\.com"[^>]*\/>\n/gm, "");
let first = true;
mustPatch("google fonts stylesheets", /^<link href="https:\/\/fonts\.googleapis\.com\/css2[^>]*\/>\n/gm, () => {
  if (first) { first = false; return '<link href="fonts/fonts.css" rel="stylesheet" />\n'; }
  return "";
});

// 2. Analytics: drop the external gtag loader (offline it is a silent no-op
//    anyway; the bundle just never attempts the request).
mustPatch("gtag loader", /^<script async src="https:\/\/www\.googletagmanager\.com\/gtag\/js[^>]*><\/script>\n/m, "");

if (/https:\/\/(fonts\.googleapis|fonts\.gstatic|www\.googletagmanager)/.test(html)) {
  throw new Error("build-www: an external Google URL survived the patch — audit index.html");
}

// 3. LOOSE-ASSET AUDIT: the bundle ships ONLY index.html + items.js +
//    difficulty.js + tutorial.js + fonts/. Any other relative src (e.g.
//    src="icons/logo.svg") 404s offline and WKWebView draws the broken-image
//    "?" glyph — exactly the menu-logo bug this guards against. All art must
//    be inline (data URI / inline SVG) or added to the copy list above.
const loose = html.match(/src="(?!data:|https?:|items\.js|difficulty\.js|tutorial\.js|fonts\/)[^"]+"/);
if (loose) {
  throw new Error("build-www: relative asset reference would 404 offline — " + loose[0]
    + " — inline it (data URI) or add the file to the bundle copy list");
}
writeFileSync(join(www, "index.html"), html);
console.log("build-www: www/ assembled (offline bundle — fonts local, gtag stripped)");
