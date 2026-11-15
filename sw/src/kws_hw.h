/*
 * kws_hw.h -- acces aux registres du peripherique kws_audio_axi (PL)
 * Base fixee dans hw/scripts/bd_system.tcl : 0x43C0_0000
 */
#ifndef KWS_HW_H
#define KWS_HW_H

#include <stdint.h>
#include "xil_io.h"

#define KWS_BASE          0x43C00000u

#define KWS_REG_CTRL      0x00u
#define KWS_REG_STATUS    0x04u
#define KWS_REG_DATA      0x08u
#define KWS_REG_FRAMES    0x0Cu
#define KWS_REG_LEDS      0x10u
#define KWS_REG_VERSION   0x14u
#define KWS_REG_LAST      0x18u
#define KWS_REG_INPUTS    0x1Cu
#define KWS_REG_THRESH    0x20u
#define KWS_REG_LEVEL     0x24u

/* CTRL */
#define CTRL_CAPTURE      (1u << 0)
#define CTRL_FIFO_CLEAR   (1u << 1)
#define CTRL_REINIT       (1u << 2)
#define CTRL_LOOPBACK     (1u << 3)
#define CTRL_CH_LEFT      (0u << 4)
#define CTRL_CH_RIGHT     (1u << 4)
#define CTRL_CH_MIX       (2u << 4)
#define CTRL_LINE_IN      (1u << 6)   /* entree ligne (jack bleu) au lieu du micro */

/* STATUS */
#define ST_INIT_DONE      (1u << 0)
#define ST_I2C_ERR        (1u << 1)
#define ST_OVERFLOW       (1u << 2)
#define ST_EMPTY          (1u << 3)
#define ST_FULL           (1u << 4)
#define ST_MCLK_LOCKED    (1u << 5)
#define ST_LEVEL(s)       (((s) >> 16) & 0x3FFFu)

/* LEDS */
#define LEDS_SW_CTRL      (1u << 31)
#define LEDS_R            (1u << 4)
#define LEDS_G            (1u << 5)
#define LEDS_B            (1u << 6)

#define KWS_VERSION_ID    0x4B575331u

static inline uint32_t kws_rd(uint32_t off)             { return Xil_In32(KWS_BASE + off); }
static inline void     kws_wr(uint32_t off, uint32_t v) { Xil_Out32(KWS_BASE + off, v); }

#endif
