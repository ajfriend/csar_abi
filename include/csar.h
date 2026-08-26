/* csar.h — the C declaration of the csar ABI.
 *
 * Mirrors src/capi.zig one-for-one; capi.zig is the source of truth.
 * Native contract only: the wasm-only doors (static-buffer accessors)
 * are deliberately absent — native hosts allocate their own buffers.
 */
#ifndef CSAR_H
#define CSAR_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Return codes for the csar_solve call itself: 0 = "ran, the outcome
 * is in csar_result.status"; nonzero = "could not run". */
#define CSAR_OK 0
#define CSAR_INSUFFICIENT_POINTS 1
#define CSAR_INVALID_TOLERANCE 2
#define CSAR_COPLANAR_INPUT 3
#define CSAR_OUT_OF_MEMORY 4
#define CSAR_INTERNAL 5
#define CSAR_INVALID_METHOD 6

/* csar_result.status values on CSAR_OK — which outcome the solver
 * produced. */
#define CSAR_STATUS_CONVERGED 0
#define CSAR_STATUS_INFEASIBLE 1
#define CSAR_STATUS_DID_NOT_CONVERGE 2
#define CSAR_STATUS_PRECISION_FLOOR 3

/* method in-param values; CSAR_METHOD_AUTO is upstream's alias for
 * its recommended path. csar_result.method reports the concrete path
 * that produced the outcome (-1 when the outcome carries none). */
#define CSAR_METHOD_TRUST 0
#define CSAR_METHOD_AUTO 1

/* The one declared result layout, shared by every target. status
 * selects which fields are meaningful:
 *   converged:        q, sigma, gap, method, n_iters
 *   did_not_converge,
 *   precision_floor:  q, sigma, gap, gap_floor, method, n_iters
 *                     (last certified iterate; not a certified cone)
 *   infeasible:       residual
 * Fields the variant doesn't define hold NaN (doubles) / -1 / 0. */
typedef struct csar_result {
    /* Eigenbasis of A, row-major: q[r*3 + c] = Q(r, c). Column i is
     * the unit eigenvector paired with sigma[i]; column 0 is the cone
     * axis. */
    double q[9];
    /* Eigenvalues pairing with q's columns. sigma[0] is the structural
     * axial eigenvalue (1/sqrt(3)); the cone's aspect ratio is
     * sigma[2]/sigma[1]. */
    double sigma[3];
    /* Duality gap. Certified <= gap_tol only when status is
     * CSAR_STATUS_CONVERGED; on uncertified outcomes, the gap at the
     * last certified iterate. */
    double gap;
    /* Smallest gap certifiable at f64 for this input's geometry
     * (uncertified outcomes only). */
    double gap_floor;
    /* Farkas witness magnitude (infeasible only). */
    double residual;
    /* CSAR_STATUS_* on CSAR_OK; -1 otherwise. */
    int32_t status;
    /* CSAR_METHOD_* concrete path tag; -1 when the outcome has none. */
    int32_t method;
    /* Total solver iterations. */
    uint32_t n_iters;
} csar_result;

/* Solve the spherical aspect-ratio problem for a point set.
 *
 * pts is an interleaved (n, 3) row-major buffer [x0, y0, z0, ...] of
 * unit vectors. gap_tol, n_hull, coplanarity_tol, and max_outer map
 * onto the upstream SolveOptions; pass CSAR_METHOD_AUTO for the
 * recommended solver path.
 *
 * out is fully written on every return. out_lambdas, if non-NULL,
 * must have length n: it is zeroed, and on a converged outcome the
 * dual multipliers are scattered into it at the caller's own point
 * order — nonzero exactly on the support set, zeroed on every
 * non-converged outcome. NULL skips certificate marshaling. */
int32_t csar_solve(const double *pts, uint32_t n, double gap_tol,
                   int32_t n_hull, double coplanarity_tol,
                   uint32_t max_outer, int32_t method, csar_result *out,
                   double *out_lambdas);

/* Version of this ABI (doors, csar_result, code tables) and of the
 * csar solver it is built over. The ABI version tracks ABI change,
 * not upstream releases. */
const char *csar_abi_version(void);
const char *csar_upstream_version(void);

#ifdef __cplusplus
}
#endif

#endif /* CSAR_H */
