// The JS half of the declaration-drift gate: checks csar.js against
// the ABI reference emitted from capi.zig (gate/emit_abi_json.zig) and
// against the built module, by driving it.
//
//   node gate/gate_js.mjs <abi.json> <csar.wasm>
//
// Exits nonzero, naming the decl, on any disagreement. The doors are
// not checked here: csar.js validates them itself in init(), so a
// mismatched module fails for real callers too, not only in CI.
import { readFileSync } from 'node:fs';
import * as csar from '../csar.js';

const [jsonPath, wasmPath] = process.argv.slice(2);
const ref = JSON.parse(readFileSync(jsonPath, 'utf8'));
const fail = [];

// 1. Constants, both ways: every CSAR_* capi declares must be exported
//    with the same value, and csar.js must export no CSAR_* that capi
//    has dropped. (The C gate's exhaustive partition is the model.)
for (const [name, value] of Object.entries(ref.constants)) {
  if (!(name in csar)) fail.push(`csar.js is missing ${name}`);
  else if (csar[name] !== value) {
    fail.push(`${name}: csar.js has ${csar[name]}, capi has ${value}`);
  }
}
for (const name of Object.keys(csar)) {
  if (name.startsWith('CSAR_') && !(name in ref.constants)) {
    fail.push(`csar.js exports ${name}, which capi does not declare`);
  }
}

// 2. The struct csar.js reads by byte offset — offset AND type, since
//    retyping a field moves nothing but changes the view it needs.
const VIEW_OF = { f64: 'Float64Array', i32: 'Int32Array', u32: 'Uint32Array' };
for (const [field, { offset, type }] of Object.entries(ref.layout)) {
  const got = csar.RESULT_LAYOUT[field];
  if (got === undefined) fail.push(`RESULT_LAYOUT is missing .${field}`);
  else if (got !== offset) {
    fail.push(`RESULT_LAYOUT.${field}: csar.js has ${got}, capi has ${offset}`);
  }
  const scalar = type.replace(/\[\d+\]$/, '');
  if (!(scalar in VIEW_OF)) fail.push(`.${field} is ${type}, which csar.js has no view for`);
}
if (csar.RESULT_LAYOUT.sizeof !== ref.sizeof) {
  fail.push(`RESULT_LAYOUT.sizeof: csar.js has ${csar.RESULT_LAYOUT.sizeof}, capi has ${ref.sizeof}`);
}
for (const field of Object.keys(csar.RESULT_LAYOUT)) {
  if (field !== 'sizeof' && !(field in ref.layout)) {
    fail.push(`RESULT_LAYOUT.${field} is not a csar_result field`);
  }
}

// 3. The status and method names csar.js publishes must cover every
//    code capi declares for them, and invent none.
const named = (prefix, table) => {
  for (const [name, value] of Object.entries(ref.constants)) {
    if (!name.startsWith(prefix) || name.endsWith('_NONE')) continue;
    if (!(value in table)) fail.push(`${name} has no name in csar.js`);
  }
};
named('CSAR_STATUS_', csar.STATUS_NAME);
// CSAR_METHOD_AUTO is an in-param value: the result never reports it.
if (!(csar.CSAR_METHOD_TRUST in csar.METHOD_NAME)) {
  fail.push('CSAR_METHOD_TRUST has no name in csar.js');
}

// 4. And the file has to actually drive the module end to end. The
//    inputs are the canonical per-outcome sets from csar_zig's
//    examples/status.zig, the same ones tests/smoke_test.zig uses.
const ex = await csar.init(readFileSync(wasmPath));
const r = csar.solve([[1, 0, 0], [0, 1, 0], [0, 0, 1]]);
if (r.status !== 'converged') fail.push(`octant solved as ${r.status}`);
if (Math.abs(r.aspectRatio - 1) > 1e-6) fail.push(`octant aspect ${r.aspectRatio} != 1`);
if (r.lambdas.length !== 3 || !r.lambdas.every((l) => l > 0)) {
  fail.push(`octant support set: ${JSON.stringify([...r.lambdas])}`);
}
// Flat input must reach the same answer as rows.
const flat = csar.solve(new Float64Array([1, 0, 0, 0, 1, 0, 0, 0, 1]));
if (flat.gap !== r.gap) fail.push('flat and row input disagree');
const inf = csar.solve([[1, 0, 0], [-1, 0, 0], [0, 1, 0]]);
if (inf.status !== 'infeasible') fail.push(`antipodal solved as ${inf.status}`);
if (inf.method !== null) fail.push(`infeasible reported method ${inf.method}`);
const v = csar.versions();
for (const [which, s] of Object.entries(v)) {
  if (!/^\d+\.\d+\.\d+$/.test(s)) fail.push(`${which} version reads ${JSON.stringify(s)}`);
}
// The cap is the declaration's to enforce, before it writes.
try {
  csar.solve(new Float64Array(3 * (csar.CSAR_WASM_MAX_PTS + 1)));
  fail.push('an oversized input was not rejected');
} catch (e) {
  if (!/at most/.test(e.message)) fail.push(`oversized input: ${e.message}`);
}

if (fail.length) {
  console.error('declaration drift:\n  ' + fail.join('\n  '));
  process.exit(1);
}
console.log(`csar.js gate: ok (abi ${v.abi}, solver ${v.solver}, ${Object.keys(ex).length} exports)`);
