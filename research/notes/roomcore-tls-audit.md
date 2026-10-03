# RoomCore TLS audit — laptop 2026-10-03

The ten-site baseline reproduced **88** `net_error -107` TLS failures. Every
failing socket connected to `[::]:443`, using local `[::1]`, and received fatal
TLS alert **80**. BoringSSL reports reason **1080**,
`SSL_R_TLSV1_ALERT_INTERNAL_ERROR`, at `ssl/tls_record.cc:491`. This is a peer
alert from a locally redirected endpoint, not a certificate validation failure.

A read-only macOS resolver query for `static.adsafeprotected.com` returned
IPv6 `::` and IPv4 `0.0.0.0`. There is no matching /etc/hosts entry and the
unprivileged listener query did not identify the filter. The resolver data and
socket evidence establish local DNS sinkholing/interception; the filtering
product is not identified. No filter configuration was changed.

| Host | Failed TLS connections | Request component annotations |
|---|---:|---|
| a.et.nytimes.com | 6 | blink_resource_loader |
| als-svc.nytimes.com | 4 | blink_resource_loader |
| api.permutive.com | 2 | socket retry/preconnect; no URL request |
| c.amazon-adsystem.com | 4 | blink_resource_loader |
| cdn.adsafeprotected.com | 2 | socket retry/preconnect; no URL request |
| cdn.concert.io | 4 | blink_resource_loader |
| cdn.optimizely.com | 10 | blink_resource_loader |
| cdn.permutive.com | 2 | socket retry/preconnect; no URL request |
| cdn.tinypass.com | 2 | blink_resource_loader |
| geolocation.onetrust.com | 4 | blink_resource_loader |
| htlbid.com | 2 | blink_resource_loader |
| pagead2.googlesyndication.com | 8 | blink_resource_loader |
| pub.doubleverify.com | 2 | blink_resource_loader |
| region1.google-analytics.com | 2 | blink_resource_loader |
| rumcdn.geoedge.be | 2 | blink_resource_loader |
| sb.scorecardresearch.com | 2 | blink_resource_loader |
| securemetrics.apple.com | 2 | blink_resource_loader |
| securepubads.g.doubleclick.net | 6 | blink_resource_loader |
| static.adsafeprotected.com | 2 | socket retry/preconnect; no URL request |
| static.chartbeat.com | 2 | blink_resource_loader |
| tag.wknd.ai | 2 | blink_resource_loader |
| warp.media.net | 2 | blink_resource_loader |
| worldrealize.com | 2 | blink_resource_loader |
| www.google-analytics.com | 4 | socket retry/preconnect; no URL request |
| www.googletagmanager.com | 6 | blink_resource_loader |
| www.googletagservices.com | 2 | blink_resource_loader |

All 88 hosts are attributed using socket dependency edges and socket-pool
GroupId destination serialization; the partition-key host is excluded. Eight
NetLog summarizer regression tests pass, including unbound retry attribution.

B-3 originally counted approximately 220 failures on the Mac mini without
retaining a matching host-attributed NetLog here. The laptop reproduces the
same error code and names its cause by host; the precise mini count cannot be
retrospectively attributed from stderr alone. These are page-initiated ad/
measurement resources during open10, distinct from the idle background audit.

Raw local evidence: `baseline-laptop-initial/open10/netlog.json` (ignored).
Before/after 600-second idle request lists remain pending.
