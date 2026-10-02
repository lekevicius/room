// Copyright 2026 Jonas Lekevicius. All rights reserved.

#ifndef ROOM_CORE_PUBLIC_ROOMEXPORT_H_
#define ROOM_CORE_PUBLIC_ROOMEXPORT_H_

// Chromium compiles with -fvisibility=hidden; every class and function of the
// public API is exported explicitly.
#define ROOM_EXPORT __attribute__((visibility("default")))

#endif  // ROOM_CORE_PUBLIC_ROOMEXPORT_H_
