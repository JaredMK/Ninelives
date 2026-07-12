// Flip the app between its two modes (see app/README.md):
//   dev     — the webview loads the DEPLOYED GitHub Pages game remotely
//             (instant iteration: push to neural-redesign, relaunch the app).
//   release — the webview loads the BUNDLED www/ assets (fully offline;
//             this is the only mode allowed for App Store submission).
// After flipping, run:  npm run sync   (rebuilds www/ + updates the iOS project)
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DEV_URL = "https://jaredmk.github.io/Ninelives/neural/";
const mode = process.argv[2];
if (mode !== "dev" && mode !== "release") {
  console.error("usage: node scripts/set-mode.mjs <dev|release>");
  process.exit(1);
}
const cfgPath = join(dirname(dirname(fileURLToPath(import.meta.url))), "capacitor.config.json");
const cfg = JSON.parse(readFileSync(cfgPath, "utf8"));
if (mode === "dev") cfg.server = { url: DEV_URL };
else delete cfg.server;
writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + "\n");
console.log("mode set to " + mode.toUpperCase() + (mode === "dev" ? " (remote: " + DEV_URL + ")" : " (bundled www/, offline)"));
console.log("now run: npm run sync");
