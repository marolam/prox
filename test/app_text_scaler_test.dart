import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prox/utils/app_text_scaler.dart';

class _NonlinearSystemScaler extends TextScaler {
  const _NonlinearSystemScaler();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 2 : fontSize * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  test('in-app preference preserves nonlinear OS accessibility scaling', () {
    const scaler = AppTextScaler(
      systemScaler: _NonlinearSystemScaler(),
      preference: 1.2,
    );
    expect(scaler.scale(10), 24);
    expect(scaler.scale(40), 72);
  });

  test(
    'default preference preserves OS setting instead of reverting to 1x',
    () {
      const scaler = AppTextScaler(
        systemScaler: TextScaler.linear(2),
        preference: 1,
      );
      expect(scaler.scale(16), 32);
    },
  );

  test('invalid preferences are bounded without replacing system scaling', () {
    expect(
      const AppTextScaler(
        systemScaler: TextScaler.linear(2),
        preference: 9,
      ).scale(10),
      32,
    );
    expect(
      const AppTextScaler(
        systemScaler: TextScaler.linear(2),
        preference: -1,
      ).scale(10),
      18,
    );
    expect(
      const AppTextScaler(
        systemScaler: TextScaler.linear(2),
        preference: double.nan,
      ).scale(10),
      20,
    );
  });
}
