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

const STATUS_NAME = {
  [CSAR_STATUS_CONVERGED]: 'converged',
  [CSAR_STATUS_INFEASIBLE]: 'infeasible',
  [CSAR_STATUS_DID_NOT_CONVERGE]: 'did_not_converge',
  [CSAR_STATUS_PRECISION_FLOOR]: 'precision_floor',
};

const METHOD_NAME = {
  [CSAR_METHOD_TRUST]: 'trust',
  [CSAR_METHOD_NONE]: null,
};

let ex = null;

/** Instantiate the module. `src` is a URL (browser) or bytes (node). */
export async function init(src) {
  const bytes =
    typeof src === 'string' ? await (await fetch(src)).arrayBuffer() : src;
  // Freestanding: no host imports at all.
  const { instance } = await WebAssembly.instantiate(bytes, {});
  ex = instance.exports;
  return module();
}

/** The raw exports, for callers that want the doors directly. */
export function module() {
  if (!ex) throw new Error('csar: call init() first');
  return ex;
}

const cstr = (ptr) => {
  const u8 = new Uint8Array(ex.memory.buffer);
  let end = ptr;
  while (u8[end] !== 0) end++;
  return new TextDecoder().decode(u8.subarray(ptr, end));
};

/** Version of the ABI, and of the csar solver it was built over. */
export const versions = () => ({
  abi: cstr(module().csar_abi_version()),
  solver: cstr(module().csar_upstream_version()),
});

/**
 * Solve for the tightest enclosing ellipsoidal cone.
 *
 * `points` is an iterable of `[x, y, z]` unit vectors, or a flat
 * Float64Array/array of `3 * n` coordinates. Returns a plain object:
 * `{ status, method, iters }` always; `Q` (row-major 3x3), `sigma`,
 * `gap`, `aspectRatio` and `lambdas` when converged; `gap_floor` on
 * the uncertified outcomes; `residual` when infeasible.
 *
 * Throws on a nonzero call code — those mean the solve could not run.
 */
export function solve(points) {
  const e = module();
  const flat =
    ArrayBuffer.isView(points) || typeof points[0] === 'number'
      ? points
      : Array.prototype.concat.apply([], Array.from(points));
  const n = flat.length / 3;
  if (!Number.isInteger(n)) throw new Error('csar: points must be 3 per row');
  // Guard BEFORE building the view: an oversized view writes past the
  // static buffer, and solve()'s CSAR_TOO_MANY_POINTS is the backstop,
  // not the guard — this side owns the memory writes.
  if (n > CSAR_WASM_MAX_PTS) throw new Error(`csar: ${ERRORS[CSAR_TOO_MANY_POINTS]}`);

  new Float64Array(e.memory.buffer, e.ptsPtr(), 3 * n).set(flat);
  const rc = e.solve(n);
  if (rc !== CSAR_OK) {
    throw new Error(`csar: ${ERRORS[rc] ?? `error code ${rc}`}`);
  }

  // Fresh views AFTER the call: solving allocates, and growing wasm
  // memory detaches every view taken before it.
  const base = e.resultPtr();
  const f = new Float64Array(e.memory.buffer, base, RESULT_LAYOUT.residual / 8 + 1);
  const i32 = new Int32Array(e.memory.buffer, base + RESULT_LAYOUT.status, 2);
  const u32 = new Uint32Array(e.memory.buffer, base + RESULT_LAYOUT.n_iters, 1);

  const status = STATUS_NAME[i32[0]];
  const out = {
    status,
    method: METHOD_NAME[i32[1]],
    iters: u32[0],
  };
  if (status === 'infeasible') {
    out.residual = f[RESULT_LAYOUT.residual / 8];
    return out;
  }
  out.Q = Array.from(f.subarray(0, 9));
  out.sigma = Array.from(f.subarray(9, 12));
  out.gap = f[RESULT_LAYOUT.gap / 8];
  if (status === 'converged') {
    out.aspectRatio = out.sigma[2] / out.sigma[1];
    // One multiplier per input point, in the caller's order: nonzero
    // exactly on the support set.
    out.lambdas = Array.from(
      new Float64Array(e.memory.buffer, e.lambdasPtr(), n),
    );
  } else {
    out.gap_floor = f[RESULT_LAYOUT.gap_floor / 8];
  }
  return out;
}
