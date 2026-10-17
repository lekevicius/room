// Copyright 2026 Jonas Lekevicius. All rights reserved.
#ifndef ROOM_CORE_CONTENT_BLOCKING_DOMAIN_RESOLVER_H_
#define ROOM_CORE_CONTENT_BLOCKING_DOMAIN_RESOLVER_H_

#include <cstddef>

#include "third_party/rust/cxx/v1/cxx.h"

namespace room::adblock {

// adblock-rust's domain resolver: the [start, end) range of `host`'s
// registrable domain (eTLD+1) by Chromium's registry_controlled_domains,
// private registries included; (0, host.size()) when there is none. Called
// from Rust on any thread (the registry is static data).
void HostDomainRange(rust::Str host, size_t& start, size_t& end);

}  // namespace room::adblock

#endif  // ROOM_CORE_CONTENT_BLOCKING_DOMAIN_RESOLVER_H_
