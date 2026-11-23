import 'package:flutter_test/flutter_test.dart';
import 'package:sameni_vpn/main.dart';

void main() {
  group('SAMENI input validation', () {
    test('accepts IPv4 and IPv6 DNS addresses', () {
      expect(validDns('1.1.1.1'), isTrue);
      expect(validDns('2606:4700:4700::1111'), isTrue);
    });

    test('accepts HTTPS DNS-over-HTTPS endpoints', () {
      expect(validDns('https://cloudflare-dns.com/dns-query'), isTrue);
    });

    test('rejects malformed addresses and insecure DoH endpoints', () {
      expect(validDns('999.1.1.1'), isFalse);
      expect(validDns('::::'), isFalse);
      expect(validDns('http://dns.example/dns-query'), isFalse);
      expect(validDns(''), isFalse);
    });
  });

  group('SAMENI formatting', () {
    test('normalizes Persian and Arabic digits', () {
      expect(normalizeDigits('۱.۱.۱.۱'), '1.1.1.1');
      expect(normalizeDigits('١.٠.٠.١'), '1.0.0.1');
    });

    test('formats byte counters', () {
      expect(fmtBytes(1024), '1.0 KB');
      expect(fmtBytes(1048576), '1.0 MB');
    });
  });
}
