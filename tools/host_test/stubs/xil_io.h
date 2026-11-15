/* stub PC : registres simules (uniquement pour verifier que main.c compile) */
#ifndef XIL_IO_STUB_H
#define XIL_IO_STUB_H
#include <stdint.h>
static inline uint32_t Xil_In32(uintptr_t a) { (void)a; return 0; }
static inline void Xil_Out32(uintptr_t a, uint32_t v) { (void)a; (void)v; }
#endif
