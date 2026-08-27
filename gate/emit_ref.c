/* The other half of the declaration-drift gate: prints the same
 * reference gate/emit_ref.zig prints, but as a C compiler sees
 * include/csar.h — values from the #defines, layout from
 * offsetof/sizeof. Checks the header as compiled, not as text.
 *
 * Hand-listed, in capi.zig's decl order. A constant missing here or
 * in the header diffs against the Zig side, which reflects over
 * everything; a name missing from the header fails this file's
 * compile. */
#include <stdint.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include "csar.h"

static void num(const char *name, int64_t v) { printf("%s %lld\n", name, (long long)v); }
static void bits(const char *name, double v) {
    uint64_t b;
    memcpy(&b, &v, 8);
    printf("%s bits:%llx\n", name, (unsigned long long)b);
}

int main(void) {
    num("CSAR_OK", CSAR_OK);
    num("CSAR_INSUFFICIENT_POINTS", CSAR_INSUFFICIENT_POINTS);
    num("CSAR_INVALID_TOLERANCE", CSAR_INVALID_TOLERANCE);
    num("CSAR_COPLANAR_INPUT", CSAR_COPLANAR_INPUT);
    num("CSAR_OUT_OF_MEMORY", CSAR_OUT_OF_MEMORY);
    num("CSAR_INTERNAL", CSAR_INTERNAL);
    num("CSAR_INVALID_METHOD", CSAR_INVALID_METHOD);
    num("CSAR_TOO_MANY_POINTS", CSAR_TOO_MANY_POINTS);
    num("CSAR_WASM_MAX_PTS", CSAR_WASM_MAX_PTS);
    num("CSAR_STATUS_CONVERGED", CSAR_STATUS_CONVERGED);
    num("CSAR_STATUS_INFEASIBLE", CSAR_STATUS_INFEASIBLE);
    num("CSAR_STATUS_DID_NOT_CONVERGE", CSAR_STATUS_DID_NOT_CONVERGE);
    num("CSAR_STATUS_PRECISION_FLOOR", CSAR_STATUS_PRECISION_FLOOR);
    num("CSAR_METHOD_TRUST", CSAR_METHOD_TRUST);
    num("CSAR_METHOD_AUTO", CSAR_METHOD_AUTO);
    num("CSAR_STATUS_NONE", CSAR_STATUS_NONE);
    num("CSAR_METHOD_NONE", CSAR_METHOD_NONE);
    bits("CSAR_DEFAULT_GAP_TOL", CSAR_DEFAULT_GAP_TOL);
    num("CSAR_DEFAULT_N_HULL", CSAR_DEFAULT_N_HULL);
    bits("CSAR_DEFAULT_COPLANARITY_TOL", CSAR_DEFAULT_COPLANARITY_TOL);
    num("CSAR_DEFAULT_MAX_OUTER", CSAR_DEFAULT_MAX_OUTER);

    printf("offsetof q %zu\n", offsetof(csar_result, q));
    printf("offsetof sigma %zu\n", offsetof(csar_result, sigma));
    printf("offsetof gap %zu\n", offsetof(csar_result, gap));
    printf("offsetof gap_floor %zu\n", offsetof(csar_result, gap_floor));
    printf("offsetof residual %zu\n", offsetof(csar_result, residual));
    printf("offsetof status %zu\n", offsetof(csar_result, status));
    printf("offsetof method %zu\n", offsetof(csar_result, method));
    printf("offsetof n_iters %zu\n", offsetof(csar_result, n_iters));
    printf("sizeof csar_result %zu\n", (size_t)sizeof(csar_result));
    return 0;
}
