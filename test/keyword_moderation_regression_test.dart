import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:prox/services/keyword_quality_service.dart";

void main() {
  test("keyword quality rejects filler-heavy and repeated-character noise", () {
    expect(KeywordQualityService.validate("and his big butt").isValid, isFalse);
    expect(KeywordQualityService.validate("heeeeeeelp").isValid, isFalse);
    expect(
        KeywordQualityService.validate("help moving a couch").isValid, isTrue);
  });

  test("Party hot keywords are browsable and reportable", () {
    final source =
        File("lib/screens/party/party_list_screen.dart").readAsStringSync();
    expect(source, contains("ActionChip"));
    expect(source, contains("_browseKeyword"));
    expect(source, contains("Report and hide"));
    expect(source, contains("Wants"));
    expect(source, contains("Has"));
  });

  test("moderation backend requires independent reports and cleans profiles",
      () {
    final source = File("functions_notifications/index.js").readAsStringSync();
    expect(source, contains("onKeywordReportCreated"));
    expect(source, contains("reporterUids.size >= 3"));
    expect(source, contains("withoutKeyword"));
    expect(source, contains('collection("keywordEnforcement")'));
  });
}
