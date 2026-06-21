import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Test Dart AES/CBC/PKCS7 encryption against known Java output.
///
/// Java fixed test vector:
///   salt = gr3r0kzuc4tfLkT5
///   prefix64 = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
///   iv16 = BBBBBBBBBBBBBBBB
///   password = testPassword1
///   plaintext = prefix64 + password
///
/// Java output:
///   cqucJPbJHdrzCGcURjcAfjy0QqpGgPZCkKd4zlzzY/LVZZe1jvD575kLO8X0KygD+fGDa8WNiMhoijX07B5fBp0XhzzE2UWBYch0E0brpnU=
void main() {
  final salt = 'gr3r0kzuc4tfLkT5';
  final prefix64 = 'A' * 64;
  final iv16 = 'B' * 16;
  final password = 'testPassword1';
  final plaintext = prefix64 + password;

  print('plaintext: $plaintext');
  print('plaintext length: ${plaintext.length}'); // 64 + 12 = 76

  // Encrypt
  final key = utf8.encode(salt);
  final iv = utf8.encode(iv16);

  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(true, PaddedBlockCipherParameters(
    ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv)),
    null,
  ));

  final encrypted = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));
  final result = base64.encode(encrypted);

  final expected = 'cqucJPbJHdrzCGcURjcAfjy0QqpGgPZCkKd4zlzzY/LVZZe1jvD575kLO8X0KygD+fGDa8WNiMhoijX07B5fBp0XhzzE2UWBYch0E0brpnU=';

  print('\nDart result:  $result');
  print('Java expected: $expected');
  print('Match: ${result == expected}');

  if (result != expected) {
    print('\nMismatch! Analyzing...');
    final dBytes = base64.decode(result);
    final eBytes = base64.decode(expected);
    print('Dart length: ${dBytes.length}');
    print('Java length: ${eBytes.length}');
    for (var i = 0; i < dBytes.length && i < eBytes.length; i++) {
      if (dBytes[i] != eBytes[i]) {
        print('First diff at byte $i: Dart=${dBytes[i]} Java=${eBytes[i]}');
        break;
      }
    }
  }
}
