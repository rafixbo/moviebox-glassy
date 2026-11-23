import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/moviebox_api.dart';

/// Contract: when every host fails, the app must surface only the short
/// friendly message — never a raw SocketException/ClientException dump.
void main() {
  test('total-failure message is short and contains no raw error text', () {
    const msg = MovieBoxApi.kUnreachableMessage;
    expect(msg, isNotEmpty);
    expect(msg.toLowerCase(), isNot(contains('socketexception')));
    expect(msg.toLowerCase(), isNot(contains('clientexception')));
    expect(msg.toLowerCase(), isNot(contains('failed host lookup')));
    expect(msg.toLowerCase(), isNot(contains('errno')));
    expect(msg.toLowerCase(), isNot(contains('uri=')));
    expect(
      const MovieBoxException(MovieBoxApi.kUnreachableMessage).message,
      MovieBoxApi.kUnreachableMessage,
    );
  });
}
