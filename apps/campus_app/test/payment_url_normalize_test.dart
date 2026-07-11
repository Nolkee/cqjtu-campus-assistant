import 'package:flutter_test/flutter_test.dart';

import 'package:campus_app/pages/campus_card_page.dart'
    show normalizePaymentLaunchUrl;

void main() {
  test('passes through alipay deep links', () {
    expect(
      normalizePaymentLaunchUrl('alipays://platformapi/startapp?appId=1'),
      'alipays://platformapi/startapp?appId=1',
    );
    expect(
      normalizePaymentLaunchUrl('alipay://platformapi/startapp'),
      'alipay://platformapi/startapp',
    );
  });

  test('passes through https fallbacks', () {
    expect(
      normalizePaymentLaunchUrl('https://ds.alipay.com/?from=xx'),
      'https://ds.alipay.com/?from=xx',
    );
  });

  test('converts Android intent:// with scheme to alipays', () {
    const intent =
        'intent://platformapi/startapp?saId=10000007#Intent;scheme=alipays;package=com.eg.android.AlipayGphone;end';
    expect(
      normalizePaymentLaunchUrl(intent),
      'alipays://platformapi/startapp?saId=10000007',
    );
  });

  test('uses browser_fallback_url when scheme missing', () {
    const intent =
        'intent://host/path#Intent;S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fpay;end';
    expect(
      normalizePaymentLaunchUrl(intent),
      'https://example.com/pay',
    );
  });

  test('returns null for empty input', () {
    expect(normalizePaymentLaunchUrl(''), isNull);
    expect(normalizePaymentLaunchUrl('   '), isNull);
  });
}
