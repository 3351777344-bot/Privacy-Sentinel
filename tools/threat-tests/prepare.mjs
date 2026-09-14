/**
 * Copy the on-device scanner sources into a Node-runnable tree.
 *
 * The L1 scanners are written as pure TypeScript with no ArkTS imports, so the
 * exact files that get compiled into the HAP can also run under Node with
 * `--experimental-strip-types`. Two mechanical adjustments are needed, and both
 * are made here rather than in the shipping sources:
 *
 *   1. Relative import specifiers get an explicit `.ts` extension, because
 *      Node's ESM resolver requires one while ArkTS does not.
 *   2. Imports that only reference interfaces / type aliases are converted to
 *      `import type`. Type stripping erases those declarations, so a plain
 *      `import` would otherwise fail at link time looking for a runtime export.
 *      The set of type names is harvested from the sources themselves, so this
 *      stays correct as the scanner set grows.
 *
 * `services/RequirementAudit.ets` is included even though it lives outside
 * `services/scanners/`, because it decides which findings a requirement
 * violation produces and holds a copy of the server's scoring table. Both are
 * things the device gets wrong silently, so both are worth asserting here. It
 * imports only `models/`, which is pure types.
 *
 * Verifying the shipping source — rather than a hand-maintained port of it — is
 * the whole point: a passing test here is evidence about the code on the device.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const ETS_ROOT = path.resolve(here, '../../platform/harmony/entry/src/main/ets');
const OUT_ROOT = path.resolve(here, '.build');

const ENTRY_FILES = [
  'models/SecurityModels.ets',
  'models/ThreatModels.ets',
  'services/RequirementAudit.ets',
  'services/ThreatScanner.ets'
];

function listScannerFiles() {
  const scannerDir = path.join(ETS_ROOT, 'services/scanners');
  return fs.readdirSync(scannerDir)
    .filter((name) => name.endsWith('.ets'))
    .map((name) => `services/scanners/${name}`);
}

/** Collect every name that is only a compile-time construct. */
function harvestTypeNames(files) {
  const names = new Set();
  for (const relative of files) {
    const source = fs.readFileSync(path.join(ETS_ROOT, relative), 'utf8');
    const pattern = /export\s+(?:interface|type)\s+([A-Za-z_$][A-Za-z0-9_$]*)/g;
    let match = pattern.exec(source);
    while (match !== null) {
      names.add(match[1]);
      match = pattern.exec(source);
    }
  }
  return names;
}

/** Bare imported name, ignoring any `as` alias. */
function importedName(specifier) {
  const parts = specifier.trim().split(/\s+as\s+/);
  return parts[0].trim();
}

function withTsExtension(specifier) {
  if (specifier.endsWith('.ts') || specifier.endsWith('.js')) {
    return specifier;
  }
  return `${specifier}.ts`;
}

function rewriteImports(source, typeNames) {
  const importPattern = /import\s*\{([\s\S]*?)\}\s*from\s*(['"])([^'"]+)\2(\s*;?)/g;

  return source.replace(importPattern, (match, body, quote, specifier, tail) => {
    if (!specifier.startsWith('.')) {
      return match;
    }
    const target = `${quote}${withTsExtension(specifier)}${quote}${tail}`;

    const specifiers = body
      .split(',')
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
    if (specifiers.length === 0) {
      return match;
    }

    const types = specifiers.filter((entry) => typeNames.has(importedName(entry)));
    const values = specifiers.filter((entry) => !typeNames.has(importedName(entry)));

    const statements = [];
    if (types.length > 0) {
      statements.push(`import type { ${types.join(', ')} } from ${target}`);
    }
    if (values.length > 0) {
      statements.push(`import { ${values.join(', ')} } from ${target}`);
    }
    return statements.join('\n');
  });
}

function main() {
  fs.rmSync(OUT_ROOT, { recursive: true, force: true });

  const files = ENTRY_FILES.concat(listScannerFiles());
  const typeNames = harvestTypeNames(files);

  let copied = 0;
  for (const relative of files) {
    const sourcePath = path.join(ETS_ROOT, relative);
    if (!fs.existsSync(sourcePath)) {
      throw new Error(`Missing scanner source: ${relative}`);
    }
    const source = fs.readFileSync(sourcePath, 'utf8');
    const targetPath = path.join(OUT_ROOT, relative.replace(/\.ets$/, '.ts'));
    fs.mkdirSync(path.dirname(targetPath), { recursive: true });
    fs.writeFileSync(targetPath, rewriteImports(source, typeNames));
    copied++;
  }

  console.log(`Prepared ${copied} scanner sources; ${typeNames.size} type-only exports detected.`);
}

main();
