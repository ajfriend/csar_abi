/** csar.js — the JavaScript declaration of the csar ABI.
 *
 * The JavaScript counterpart to `include/csar.h`: it declares the same
 * door surface, code tables, and `csar_result` layout for callers
 * loading the wasm module, and adds the two things a C compiler would
 * otherwise do for you — instantiating the module, and reading the
 * result struct out of wasm memory at fixed byte offsets.
 * `src/capi.zig` is the source of truth for every number here;
 * `just gate-js` checks this file against it.
 *
 * Declaration only: no idiom, no packaging, no framework. An idiomatic
 * JS binding, if one is ever warranted, wraps this rather than
 * replacing it.
 *
 *   import { init, solve } from './csar.js';
 *   await init('./csar.wasm');            // URL, or bytes under node
 *   const r = solve([[1,0,0], [0,1,0], [0,0,1]]);
 *   if (r.status === 'converged') use(r.aspectRatio, r.Q);
 */

/** Call codes: 0 ran (read `csar_result.status`), nonzero could not run. */
export const CSAR_OK = 0;
export const CSAR_INSUFFICIENT_POINTS = 1;
export const CSAR_INVALID_TOLERANCE = 2;
export const CSAR_COPLANAR_INPUT = 3;
export const CSAR_OUT_OF_MEMORY = 4;
export const CSAR_INTERNAL = 5;
export const CSAR_INVALID_METHOD = 6;
export const CSAR_TOO_MANY_POINTS = 7;

/** `csar_result.status` values on CSAR_OK. */
export const CSAR_STATUS_CONVERGED = 0;
export const CSAR_STATUS_INFEASIBLE = 1;
export const CSAR_STATUS_DID_NOT_CONVERGE = 2;
export const CSAR_STATUS_PRECISION_FLOOR = 3;

/** Solver paths. AUTO is upstream's alias for its recommended path. */
export const CSAR_METHOD_TRUST = 0;
export const CSAR_METHOD_AUTO = 1;

/** "Not set": status before a CSAR_OK return, method on outcomes with no path tag. */
export const CSAR_STATUS_NONE = -1;
export const CSAR_METHOD_NONE = -1;

/** The wasm module's static input-buffer cap, points per solve. */
export const CSAR_WASM_MAX_PTS = 4096;

/** The solve options the wasm `solve` door pins — informational here,
 *  since that door takes no options. */
export const CSAR_DEFAULT_GAP_TOL = 1e-6;
export const CSAR_DEFAULT_N_HULL = 10;
export const CSAR_DEFAULT_COPLANARITY_TOL = 1e-12;
export const CSAR_DEFAULT_MAX_OUTER = 100;

/** Byte offsets and size of `csar_result` — capi.zig asserts these at comptime. */
export const RESULT_LAYOUT = Object.freeze({
  q: 0,
  sigma: 72,
  gap: 96,
  gap_floor: 104,
  residual: 112,
  status: 120,
  method: 124,
  n_iters: 128,
  sizeof: 136,
});

/** Doors this file calls. Checked at init() so a stale or mismatched
 *  module fails with a name, for real callers and not only in CI. */
const DOORS = [
  'memory', 'ptsPtr', 'resultPtr', 'lambdasPtr', 'solve',
  'csar_abi_version', 'csar_upstream_version',
];

const ERRORS = {
  [CSAR_INSUFFICIENT_POINTS]: 'need at least 3 points to define a cone',
  [CSAR_INVALID_TOLERANCE]: 'invalid tolerance',
  [CSAR_COPLANAR_INPUT]:
    'input is (near-)coplanar — points lie ~on a great circle, so no ' +
    'meaningful enclosing cone exists',
  [CSAR_OUT_OF_MEMORY]: 'out of memory',
  [CSAR_INTERNAL]: 'internal solver error — please report it',
  [CSAR_INVALID_METHOD]: 'method must be CSAR_METHOD_TRUST or CSAR_METHOD_AUTO',
  [CSAR_TOO_MANY_POINTS]: `at most ${CSAR_WASM_MAX_PTS} points per solve`,
};

/** Code -> name, for callers reading `csar_result.status` themselves.
 *  Exported so the numeric constants above are usable against what
 *  `solve` returns, and so the gate can check these spellings too. */
export const STATUS_NAME = Object.freeze({
  [CSAR_STATUS_CONVERGED]: 'converged',
  [CSAR_STATUS_INFEASIBLE]: 'infeasible',
  [CSAR_STATUS_DID_NOT_CONVERGE]: 'did_not_converge',
  [CSAR_STATUS_PRECISION_FLOOR]: 'precision_floor',
});

/** CSAR_METHOD_AUTO is an in-param value only: the result reports the
 *  concrete path it resolved to, or CSAR_METHOD_NONE. */
export const METHOD_NAME = Object.freeze({
  [CSAR_METHOD_TRUST]: 'trust',
  [CSAR_METHOD_NONE]: null,
});

// One module per import: the wasm module's input, result and lambda
// buffers are static, so an instance is single-use by construction —
// there is nothing here that a second instance would make safe.
let ex = null;

/** Instantiate the module. `src` is a URL (browser) or bytes (node). */
export async function init(src) {
  const bytes =
    typeof src === 'string' ? await (await fetch(src)).arrayBuffer() : src;
  // Freestanding: no host imports at all.
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const missing = DOORS.filter((d) => !(d in instance.exports));
  if (missing.length) {
    throw new Error(`csar: module is missing ${missing.join(', ')}`);
  }
  ex = instance.exports;
  return ex;
}

/** The raw exports, for callers that want the doors directly. */
export function module() {
  if (!ex) throw new Error('csar: call init() first');
  return ex;
}

const decoder = new TextDecoder();

const cstr = (ptr) => {
  const u8 = new Uint8Array(ex.memory.buffer);
  return decoder.decode(u8.subarray(ptr, u8.indexOf(0, ptr)));
};

/** Version of the ABI, and of the csar solver it was built over. */
export function versions() {
  const e = module();
  return { abi: cstr(e.csar_abi_version()), solver: cstr(e.csar_upstream_version()) };
}

/**
 * Solve for the tightest enclosing ellipsoidal cone.
 *
 * `points` is an array of `[x, y, z]` rows, or a flat array /
 * Float64Array of `3 * n` coordinates. Returns a plain object:
 * `{ status, method, iters }` always; `Q` (row-major 3x3), `sigma`,
 * `gap`, `aspectRatio` and `lambdas` when converged; `gap_floor` on
 * the uncertified outcomes; `residual` when infeasible.
 *
 * Throws on a nonzero call code — those mean the solve could not run.
 */
export function solve(points) {
  const e = module();
  const isFlat = ArrayBuffer.isView(points) || typeof points[0] === 'number';
  const n = isFlat ? points.length / 3 : points.length;
  if (!Number.isInteger(n)) throw new Error('csar: points must be 3 per row');
  // Guard BEFORE building the view: an oversized view writes past the
  // static buffer, and solve()'s CSAR_TOO_MANY_POINTS is the backstop,
  // not the guard — this side owns the memory writes.
  if (n > CSAR_WASM_MAX_PTS) throw new Error(`csar: ${ERRORS[CSAR_TOO_MANY_POINTS]}`);

  // Write rows straight into wasm memory. Flattening into a throwaway
  // JS array first costs several times this at every size, and its
  // garbage is what drops frames on a drag.
  const pts = new Float64Array(e.memory.buffer, e.ptsPtr(), 3 * n);
  if (isFlat) pts.set(points);
  else for (let i = 0, k = 0; i < n; i++) {
    const p = points[i];
    pts[k++] = p[0];
    pts[k++] = p[1];
    pts[k++] = p[2];
  }

  const rc = e.solve(n);
  if (rc !== CSAR_OK) {
    throw new Error(`csar: ${ERRORS[rc] ?? `error code ${rc}`}`);
  }

  // Fresh views AFTER the call: solving allocates, and growing wasm
  // memory detaches every view taken before it. Both cover the whole
  // struct, so every read indexes through RESULT_LAYOUT.
  const base = e.resultPtr();
  const f = new Float64Array(e.memory.buffer, base, RESULT_LAYOUT.sizeof / 8);
  const i = new Int32Array(e.memory.buffer, base, RESULT_LAYOUT.sizeof / 4);

  // Branch on the codes, not the display names: the names are a
  // presentation choice, the codes are the contract.
  const st = i[RESULT_LAYOUT.status / 4];
  const out = {
    status: STATUS_NAME[st],
    method: METHOD_NAME[i[RESULT_LAYOUT.method / 4]],
    iters: i[RESULT_LAYOUT.n_iters / 4],
  };
  if (st === CSAR_STATUS_INFEASIBLE) {
    out.residual = f[RESULT_LAYOUT.residual / 8];
    return out;
  }
  out.Q = Array.from(f.subarray(RESULT_LAYOUT.q / 8, RESULT_LAYOUT.sigma / 8));
  out.sigma = Array.from(f.subarray(RESULT_LAYOUT.sigma / 8, RESULT_LAYOUT.gap / 8));
  out.gap = f[RESULT_LAYOUT.gap / 8];
  if (st === CSAR_STATUS_CONVERGED) {
    out.aspectRatio = out.sigma[2] / out.sigma[1];
    // One multiplier per input point, in the caller's order: nonzero
    // exactly on the support set. `.slice` copies (so the next solve
    // can't clobber it) and is far cheaper than materializing a plain
    // Array at large n.
    out.lambdas = new Float64Array(e.memory.buffer, e.lambdasPtr(), n).slice();
  } else {
    out.gap_floor = f[RESULT_LAYOUT.gap_floor / 8];
  }
  return out;
}
