// Copyright 2026 Jonas Lekevicius. All rights reserved.
#include "room/core/content_blocking/domain_resolver.h"

#include <string>
#include <string_view>

#include "net/base/registry_controlled_domains/registry_controlled_domain.h"

namespace room::adblock {

void HostDomainRange(rust::Str host, size_t& start, size_t& end) {
  const std::string_view view(host.data(), host.size());
  start = 0;
  end = view.size();
  const std::string domain = net::registry_controlled_domains::
      GetDomainAndRegistry(
          view, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  // Hosts reach adblock-rust canonical already; the domain is their suffix.
  if (!domain.empty() && view.ends_with(domain)) {
    start = view.size() - domain.size();
  }
}

}  // namespace room::adblock
