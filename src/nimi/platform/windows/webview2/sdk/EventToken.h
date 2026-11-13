#ifndef NIMI_EVENTTOKEN_H
#define NIMI_EVENTTOKEN_H
/* Minimal eventtoken.h for MinGW/Zig toolchains that do not ship the SDK. */
typedef struct EventRegistrationToken { __int64 value; } EventRegistrationToken;
#endif
