import "dart:io";

import "package:flutter_test/flutter_test.dart";

void main() {
  final source = File(
    "android${Platform.pathSeparator}app${Platform.pathSeparator}src"
    "${Platform.pathSeparator}main${Platform.pathSeparator}kotlin"
    "${Platform.pathSeparator}com${Platform.pathSeparator}prox"
    "${Platform.pathSeparator}app${Platform.pathSeparator}MainActivity.kt",
  ).readAsStringSync();

  test("keyboard requests never force or toggle the Android IME", () {
    expect(source, isNot(contains("InputMethodManager.SHOW_FORCED")));
    expect(source, isNot(contains("toggleSoftInput(")));
    expect(
      source,
      contains("imm.showSoftInput(target, InputMethodManager.SHOW_IMPLICIT)"),
    );
  });

  test("every native editor dismissal cleans up before returning to Flutter", () {
    final dismissal = source.substring(
      source.indexOf("dialog.setOnDismissListener {"),
      source.indexOf("dialog.setOnShowListener {"),
    );
    expect(dismissal, contains("input.clearFocus()"));
    expect(dismissal, contains("hideSoftInputFromWindow(token, 0)"));
    expect(
      dismissal,
      contains(
        "WindowCompat.getInsetsController(window, decor).hide(WindowInsetsCompat.Type.ime())",
      ),
    );
    expect(dismissal, contains("ViewCompat.requestApplyInsets(decor)"));
    expect(dismissal, contains("result.success(output)"));
    expect(
      dismissal.indexOf("hideSoftInputFromWindow"),
      lessThan(dismissal.indexOf("result.success(output)")),
    );
    expect(source, contains("inputWindowToken = input.windowToken"));
    expect(source, contains("if (!dialog.isShowing) return@post"));
    expect(source, contains("activeTextInputDialog?.dismiss()"));
  });
}
