import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/moviebox_api.dart';

/// Test vectors computed independently in Python from the Rust spec
/// (same secret, same canonical layout) — the Dart port must match them.
void main() {
  const ts = 1700000000000;

  test('canonical string for visitor-login POST', () {
    final c = MovieBoxSigning.canonical(
      method: 'POST',
      url: 'https://api6.aoneroom.com/wefeed-mobile-bff/user-api/visitor-login',
      body: '{}',
      timestampMs: ts,
    );
    expect(
      c,
      'POST\napplication/json\napplication/json\n2\n1700000000000\n'
      '99914b932bd37a50b983c5e7c90ae93b\n'
      '/wefeed-mobile-bff/user-api/visitor-login',
    );
  });

  test('x-tr-signature matches Python-computed vector', () {
    expect(
      MovieBoxSigning.trSignature(
        method: 'POST',
        url: 'https://api6.aoneroom.com/wefeed-mobile-bff/user-api/visitor-login',
        body: '{}',
        timestampMs: ts,
      ),
      '1700000000000|2|GTpfX6gp1YiuBXe9TC2XDg==',
    );
  });

  test('GET canonical sorts query params and leaves body fields empty', () {
    final c = MovieBoxSigning.canonical(
      method: 'GET',
      url:
          'https://api4.aoneroom.com/wefeed-mobile-bff/subject-api/resource?subjectId=123&se=2&ep=1&page=1&perPage=20',
      body: null,
      timestampMs: ts,
    );
    expect(
      c,
      'GET\napplication/json\napplication/json\n\n1700000000000\n\n'
      '/wefeed-mobile-bff/subject-api/resource?ep=1&page=1&perPage=20&se=2&subjectId=123',
    );
    expect(
      MovieBoxSigning.trSignature(
        method: 'GET',
        url:
            'https://api4.aoneroom.com/wefeed-mobile-bff/subject-api/resource?subjectId=123&se=2&ep=1&page=1&perPage=20',
        body: null,
        timestampMs: ts,
      ),
      '1700000000000|2|Y6Xs5SO/LZIY0Roc+7gGMQ==',
    );
  });

  test('x-client-token is ts + md5(reversed ts)', () {
    expect(
      MovieBoxSigning.clientToken(ts),
      '1700000000000,e41bb805cc23fdc5541917da93d608d5',
    );
  });

  test('x-client-build stamp + md5(cert + oneroom + stamp)', () {
    expect(
      MovieBoxSigning.clientBuild(ts, 42),
      '170000000000000042.38cee5b5bf5223790645191f2c2689ce',
    );
  });

  test('signing is deterministic for the same inputs', () {
    const url = 'https://api5.aoneroom.com/wefeed-mobile-bff/subject-api/search/v2';
    const body = '{"keyword":"Avengers","page":1,"perPage":15,"subjectType":0}';
    final a = MovieBoxSigning.trSignature(
        method: 'POST', url: url, body: body, timestampMs: ts);
    final b = MovieBoxSigning.trSignature(
        method: 'POST', url: url, body: body, timestampMs: ts);
    expect(a, b);
    expect(a, startsWith('$ts|2|'));
  });
}
