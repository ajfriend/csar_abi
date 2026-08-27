// The JS half of the declaration-drift gate: checks csar.js against
// the ABI reference emitted from capi.zig (gate/emit_abi_json.zig) and
// against the built module's own export section — the shipped union of
// both comptime roots, so the wasm-only doors are covered too.
//
//   node gate/gate_js.mjs <abi.json> <csar.wasm>
//
// Exits nonzero, naming the decl, on any disagreement.
import { readFileSync } from 'node:fs';
import * as csar from '../csar.js';

const [jsonPath, wasmPath] = process.argv.slice(2);
const ref = JSON.parse(readFileSync(jsonPath, 'utf8'));
const fail = [];

// 1. Every CSAR_* constant capi declares must be exported by csar.js
//    with the same value. Reflection on the Zig side means a new
//    constant shows up here automatically.
for (const [name, value] of Object.entries(ref.constants)) {
  if (!(name in csar)) fail.push(`csar.js is missing ${name}`);
  else if (csar[name] !== value) {
    fail.push(`${name}: csar.js has ${csar[name]}, capi has ${value}`);
  }
}

// 2. The struct layout csar.js reads by byte offset.
for (const [field, offset] of Object.entries(ref.layout)) {
  const got = csar.RESULT_LAYOUT[field];
  if (got === undefined) fail.push(`RESULT_LAYOUT is missing .${field}`);
  else if (got !== offset) {
    fail.push(`RESULT_LAYOUT.${field}: csar.js has ${got}, capi has ${offset}`);
  }
}
for (const field of Object.keys(csar.RESULT_LAYOUT)) {
  if (!(field in ref.layout)) fail.push(`RESULT_LAYOUT.${field} is not a csar_result field`);
}

// 3. Every door csar.js calls must exist in the module it loads.
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const DOORS = [
  'memory', 'ptsPtr', 'resultPtr', 'lambdasPtr', 'solve',
  'csar_abi_version', 'csar_upstream_version',
];
for (const door of DOORS) {
  if (!(door in instance.exports)) fail.push(`the wasm module exports no ${door}`);
}

// 4. And the file has to actually drive it end to end.
await csar.init(readFileSync(wasmPath));
const r = csar.solve([[1, 0, 0], [0, 1, 0], [0, 0, 1]]);
if (r.status !== 'converged') fail.push(`octant solved as ${r.status}`);
if (Math.abs(r.aspectRatio - 1) > 1e-6) fail.push(`octant aspect ${r.aspectRatio} != 1`);
if (r.lambdas.length !== 3 || !r.lambdas.every((l) => l > 0)) {
  fail.push(`octant support set: ${JSON.stringify(r.lambdas)}`);
}
const inf = csar.solve([[1, 0, 0], [-1, 0, 0], [0, 1, 0]]);
if (inf.status !== 'infeasible') fail.push(`antipodal solved as ${inf.status}`);
if (inf.method !== null) fail.push(`infeasible reported method ${inf.method}`);
const v = csar.versions();
for (const [which, s] of Object.entries(v)) {
  if (!/^\d+\.\d+\.\d+$/.test(s)) fail.push(`${which} version reads ${JSON.stringify(s)}`);
}

if (fail.length) {
  console.error('declaration drift:\n  ' + fail.join('\n  '));
  process.exit(1);
}
console.log(`csar.js gate: ok (abi ${v.abi}, solver ${v.solver})`);
