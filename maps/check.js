#!/usr/bin/env node
/* Validate authored map file(s) from the command line.
   Usage: node maps/check.js maps/diamonds-1.map [more.map ...]
   With no args, checks every file listed in manifest.json. */
'use strict';

const fs = require('fs');
const path = require('path');
const MapEngine = require('./map-engine.js');

function checkFile(file) {
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch (e) {
    console.error(`✗ ${file}: cannot read (${e.message})`);
    return false;
  }
  const { ok, errors, model } = MapEngine.parseAndValidate(text);
  if (ok) {
    const order = model.order ? ` (order ${model.order.n} of ${model.order.of})` : '';
    console.log(`✓ ${file}: OK — phase "${model.phase}"${order}, ${model.nodes.length} nodes, ${model.links.length} links`);
    return true;
  }
  console.error(`✗ ${file}: ${errors.length} problem(s)`);
  for (const e of errors) {
    console.error(`    ${e.line ? 'line ' + e.line : 'file'}: ${e.message}`);
  }
  return false;
}

let files = process.argv.slice(2);
if (!files.length) {
  const dir = __dirname;
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  files = manifest.maps.map(f => path.join(dir, f));
}

let allOk = true;
for (const f of files) if (!checkFile(f)) allOk = false;
process.exit(allOk ? 0 : 1);
