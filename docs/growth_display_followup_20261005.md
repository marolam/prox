# Growth display follow-up: 0.20.2, build 29

Physical verification of build 28 confirmed the Dashboard stream repair, Offers tab transitions and a short support draft submitted with correct device metadata. It also exposed two older display gaps: Settings/Profile rendered a static 80% Trust badge, and Party queried incoming referral badges through a collection-group read that the existing scoped rules reject.

This follow-up uses the canonical account Trust value and reads incoming referral badges only from exact documents for confirmed Party members. Referral intent alone must not produce a verified badge. Accepted Party membership and server reward qualification remain authoritative.

The verified build-28 recovery checkpoint is `artifacts/rollback/pre-display-followup28-20261005T171450872575Z`, mirrored at `C:/Users/marty/Documents/ProxRollback/pre-display-followup28-20261005T171450872575Z`. All 133 files/118,942,713 bytes matched SHA-256 and size. It preserves source HEAD `3a7005218b28988e9d47374a96e3b1871d97879d`, published app source `57c8fcfb1f3acb0eb9aee3632ff93f95806b276b`, the verified signed build-28 APK, Git state and live configuration. The exact installed debug build-28 APK and complete phone-data checkpoint are separately preserved and mirrored at `artifacts/release/growth-hotfix28-phone-qa-20261005T171213Z`. The original pre-growth recovery baseline and build-27 checkpoints remain unchanged.

Local validation passed: analyzer clean; 399 Flutter tests passed with three existing skips; all 170 backend emulator tests passed without skips; 24 release-tool tests passed; Android/iOS Firebase registrations match the intended project. New regressions cover live/zero/error Trust scores, reopening and account changes, exact verified referral paths, independent listener cancellation and existing referral permissions. Firestore rules and indexes have no changes.

Package verification, physical retesting and distribution are pending. Background matching, Pro/Business distribution gates and the existing tester-stage rollout policy retain their previous configuration. Public latest remains build 26.
