@TestOn('vm')
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:test/test.dart';

void main() {
  group('SSL pinning', () {
    final Dio dio = Dio()..options.baseUrl = 'https://httpbun.local/';
    final expectedHostString = 'httpbun.local';

    test('trusted host allowed with no approver', () async {
      dio.httpClientAdapter = Http2Adapter(
        ConnectionManager(
          idleTimeout: Duration(seconds: 10),
        ),
      );

      final res = await dio.get('get');
      expect(res, isNotNull);
      expect(res.data, isNotNull);
      expect(res.data.toString(), contains(expectedHostString));
    });

    test('untrusted host rejected with no approver', () async {
      DioException? error;
      try {
        dio.httpClientAdapter = Http2Adapter(
          ConnectionManager(
            idleTimeout: Duration(seconds: 10),
            onClientCreate: (url, config) {
              // Consider all hosts untrusted
              config.context = SecurityContext(withTrustedRoots: false);
            },
          ),
        );
        await dio.get('get');
        fail('did not throw');
      } on DioException catch (e) {
        error = e;
      }
      expect(error, isNotNull);
    });

    test('trusted certificate tested and allowed', () async {
      bool approved = false;
      dio.httpClientAdapter = Http2Adapter(
        ConnectionManager(
          idleTimeout: Duration(seconds: 10),
          onClientCreate: (url, config) {
            config.validateCertificate = (certificate, host, port) {
              approved = true;
              return true;
            };
          },
        ),
      );
      final res = await dio.get('get');
      expect(approved, true);
      expect(res, isNotNull);
      expect(res.data, isNotNull);
      expect(res.data.toString(), contains(expectedHostString));
    });

    test(
      'untrusted certificate tested and allowed',
      () async {
        final expectedHostString = 'pub.dev';
        // NOTE: Run scripts/prepare_pinning_certs.sh
        // to download the current certs to the file below.
        //
        // OpenSSL output like: SHA256 Fingerprint=EE:5C:E1:DF:A7:A4...
        // All badssl.com hosts have the same cert, they just have TLS
        // setting or other differences (like host name) that make them bad.
        final lines = File('test/_pinning_http2.txt').readAsLinesSync();
        final fingerprint =
            lines.first.split('=').last.toLowerCase().replaceAll(':', '');

        bool badCert = false;
        bool approved = false;
        String? badCertSubject;
        String? approverSubject;
        String? badCertSha256;
        String? approverSha256;

        final dio = Dio();
        dio.options.baseUrl = 'https://pub.dev/';
        dio.httpClientAdapter = Http2Adapter(
          ConnectionManager(
            idleTimeout: Duration(seconds: 10),
            onClientCreate: (url, config) {
              config.context = SecurityContext(withTrustedRoots: false);
              config.onBadCertificate = (certificate) {
                badCert = true;
                badCertSubject = certificate.subject.toString();
                badCertSha256 = sha256.convert(certificate.der).toString();
                return true;
              };
              config.validateCertificate = (certificate, host, port) {
                if (certificate == null) fail('must include a certificate');
                approved = true;
                approverSubject = certificate.subject.toString();
                approverSha256 = sha256.convert(certificate.der).toString();
                return true;
              };
            },
          ),
        );

        final res = await dio.get(
          'get',
          options: Options(validateStatus: (status) => true),
        );
        expect(badCert, true);
        expect(approved, true);
        expect(badCertSubject, isNotNull);
        expect(badCertSubject, isNot(contains(expectedHostString)));
        expect(badCertSha256, isNot(fingerprint));
        expect(approverSubject, isNotNull);
        expect(approverSubject, contains(expectedHostString));
        expect(approverSha256, fingerprint);
        expect(approverSubject, isNot(badCertSubject));
        expect(approverSha256, isNot(badCertSha256));
        expect(res, isNotNull);
        expect(res.data, isNotNull);
        expect(res.data.toString(), contains(expectedHostString));
      },
      tags: ['tls'],
    );

    test('2 requests == 1 approval', () async {
      int approvalCount = 0;
      dio.httpClientAdapter = Http2Adapter(
        ConnectionManager(
          // allow connection reuse
          idleTimeout: Duration(seconds: 20),
          onClientCreate: (url, config) {
            config.validateCertificate = (certificate, host, port) {
              approvalCount++;
              return true;
            };
          },
        ),
      );

      Response res = await dio.get('get');
      final firstTime = res.headers['date'];
      expect(approvalCount, 1);
      expect(res.data, isNotNull);
      expect(res.data.toString(), contains(expectedHostString));
      await Future.delayed(Duration(seconds: 1));
      res = await dio.get('get');
      final secondTime = res.headers['date'];
      expect(approvalCount, 1);
      expect(firstTime, isNot(secondTime));
      expect(res.data, isNotNull);
      expect(res.data.toString(), contains(expectedHostString));
    });
  });
}
