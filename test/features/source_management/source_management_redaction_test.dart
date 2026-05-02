import 'package:flutter_test/flutter_test.dart';
import 'package:venera/features/sources/comic_source/source_management_redaction.dart';

void main() {
  test('source diagnostics redact auth headers device identifiers and signatures', () async {
    final input = <String, Object?>{
      'headers': <String, String>{
        'Authorization': 'Bearer abc',
        'X-Auth-Signature': 'sig',
        'DEVICEINFO': 'iphone',
        'Accept': 'application/json',
      },
      'pseudoId': 'id-123',
    };

    final output = redactSourceDiagnosticData(input);
    final headers = output['headers']! as Map<String, Object?>;

    expect(headers['Authorization'], '<redacted>');
    expect(headers['X-Auth-Signature'], '<redacted>');
    expect(headers['DEVICEINFO'], '<redacted>');
    expect(headers['Accept'], 'application/json');
    expect(output['pseudoId'], '<redacted>');
  });

  test('source diagnostics redact signed query parameters', () async {
    final uri = Uri.parse(
      'https://example.com/index.json?token=abc&x-auth-signature=sig&page=1',
    );

    final redacted = redactSourceDiagnosticUri(uri).toString();

    expect(redacted, contains('token=%3Credacted%3E'));
    expect(redacted, contains('x-auth-signature=%3Credacted%3E'));
    expect(redacted, contains('page=1'));
  });

  test('source diagnostics do not persist raw source script content by default', () async {
    const script = 'function source(){return "secret";}';
    final redacted = redactSourceScriptForDiagnostics(script);
    expect(redacted, '<redacted_script_content>');
    expect(redacted, isNot(contains('secret')));
  });
}
