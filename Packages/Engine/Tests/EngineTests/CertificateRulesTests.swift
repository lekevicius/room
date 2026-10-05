import Engine
import Testing

/// ROADMAP 2.6: the certificate interstitial proceeds only for non-HSTS hosts.
@Suite("Certificate errors: when proceeding is allowed")
struct CertificateRulesTests {
    @Test("A host with HSTS never proceeds; without it, overridable errors do")
    func knownPolicy() {
        #expect(!CertificateRules.isOverridable(code: -202, host: "bank.example", strictTransportSecurity: true))
        #expect(CertificateRules.isOverridable(code: -202, host: "bank.example", strictTransportSecurity: false))
        #expect(CertificateRules.isOverridable(code: -201, host: "expired.example", strictTransportSecurity: false))
    }

    @Test("Revoked, invalid and interception errors never proceed")
    func hardErrors() {
        for code in [-206, -207, -217, -150] {
            #expect(!CertificateRules.isOverridable(code: code, host: "localhost", strictTransportSecurity: false))
        }
    }

    @Test("When the engine cannot tell, only local hosts and IP addresses proceed")
    func unknownPolicy() {
        for host in ["localhost", "dev.localhost", "app.test", "printer.local", "nas.home.arpa", "127.0.0.1", "192.168.1.20", "[::1]", "LOCALHOST."] {
            #expect(CertificateRules.isOverridable(code: -202, host: host, strictTransportSecurity: nil), "\(host)")
        }
        for host in ["example.com", "self-signed.badssl.com", "my.dev", "localhost.example.com", ""] {
            #expect(!CertificateRules.isOverridable(code: -202, host: host, strictTransportSecurity: nil), "\(host)")
        }
    }
}
