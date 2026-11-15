#ifndef XTIME_L_STUB_H
#define XTIME_L_STUB_H
typedef unsigned long long XTime;
#define COUNTS_PER_SECOND 333333333ULL
static inline void XTime_GetTime(XTime *t) { *t = 0; }
#endif
