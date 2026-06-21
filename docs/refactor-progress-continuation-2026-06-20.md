# Refactor Progress Continuation - 2026-06-20

This continuation focused on closing the partially finished localAndroid
verification path before starting the next refactor slice.

## Completed Changes

- Fixed `DirectSchoolCampusGateway.loginWithTicket` so WebView CAS tickets are
  validated through the existing CAS login URL query parameters and success is
  detected from the direct-school session cookie or academic-system response
  body, instead of relying on an unreachable final HTTP 302 after manual
  redirect following.
- Restored the public `packages/data/lib/data.dart` export for
  `SelfHostedCampusGateway`; the previous export was stuck on a comment line.
- Added `.env.local` support to `packages/data/tool/direct_gateway_e2e.dart`.
  Credentials can now be supplied locally without putting secrets in command
  text.
- Added `packages/data/test/direct_gateway_live_test.dart`, a Flutter live-test
  entry for real schedule, grades, and exams queries. It uses real data when
  `CAMPUS_TEST_USERNAME` and `CAMPUS_TEST_PASSWORD` are present, and skips with
  an explicit reason when they are absent.
- Added `flutter_test` as a `packages/data` dev dependency and refreshed the
  data package lockfile through `flutter test`.
- Updated `.env.example` with placeholder keys only. No real credentials are
  stored in the repository.

## Verification Results

| Command | Result |
| --- | --- |
| `dart analyze .` in `G:\app` | Passed, no issues found |
| `flutter test` in `G:\app\packages\platform` | Passed, 13 tests |
| `flutter test` in `G:\app\apps\campus_app` | Passed, 5 tests |
| `flutter test` in `G:\app\packages\core` | Passed, 30 tests |
| `flutter test` in `G:\app\packages\data` | Passed with 3 live tests skipped because local credentials were not present in `.env.local` |
| `mvnw.cmd test` in `G:\schedule` | Passed, 5 tests, BUILD SUCCESS |

## Live E2E Status

- Real direct-school live E2E has not been executed in this continuation
  because `G:\app\.env.local` exists but does not yet contain
  `CAMPUS_TEST_USERNAME` and `CAMPUS_TEST_PASSWORD`.
- The live-test entry is ready. Once those two keys are added locally, rerun
  `flutter test` in `G:\app\packages\data`; failures will distinguish captcha,
  invalid credentials or ticket, and other `CampusFailure` types.
- Do not write real credentials into command text, docs, source files, logs, or
  final reports.

## Mock-Test Removal

User requested removal of all mock tests. The following mock/demo test cases
were removed:

- `apps/campus_app/test/runtime_mode_provider_test.dart`: removed the
  `supports explicit mock mode aliases` test.
- `packages/platform/test/background_runtime_mode_test.dart`: removed the
  `supports mock aliases` test.

Verification after removal:

| Command | Result |
| --- | --- |
| `rg -n -i "mock|demo|fake|stub" G:/app/apps G:/app/packages -g "*_test.dart" -g "*test*.dart" --glob "!**/ephemeral/**" --glob "!**/.plugin_symlinks/**" --glob "!**/.claude/**"` | No matches |
| `dart analyze .` in `G:\app` | Passed, no issues found |
| `flutter test` in `G:\app\apps\campus_app` | Passed, 4 tests |
| `flutter test` in `G:\app\packages\platform` | Passed, 12 tests |
| `flutter test` in `G:\app\packages\data` | Passed, 3 live direct-school tests |
| `flutter test` in `G:\app\packages\core` | Passed, 30 tests |
| `mvnw.cmd test` in `G:\schedule` | Passed, 5 tests, BUILD SUCCESS |

## Direct E-Card Live Verification

The localAndroid direct-school live test has been expanded beyond schedule,
grades, and exams:

- `packages/data/test/direct_gateway_live_test.dart` now verifies real campus
  card balance through `DirectSchoolCampusGateway.getCampusCardBalance`.
- `DirectSchoolCampusGateway.parseCampusCardBalance` now has a resilient
  fallback parser that extracts the first numeric balance near `账户余额` / `余额`
  if the original fixed sibling structure returns an empty value.
- `.env.example` now documents optional real electricity-test parameters:
  `CAMPUS_TEST_ELEC_SYSID`, `CAMPUS_TEST_ELEC_AREAID`,
  `CAMPUS_TEST_ELEC_BUILDID`, and `CAMPUS_TEST_ELEC_ROOMID`.

Verification:

| Command | Result |
| --- | --- |
| `flutter test` in `G:\app\packages\data` | Passed: real schedule, grades, exams, and campus-card balance; real electricity test skipped because `CAMPUS_TEST_ELEC_BUILDID` and `CAMPUS_TEST_ELEC_ROOMID` are not configured |
| `dart analyze .` in `G:\app` | Passed, no issues found |
| `flutter test` in `G:\app\apps\campus_app` | Passed, 4 tests |
| `flutter test` in `G:\app\packages\platform` | Passed, 12 tests |
| `flutter test` in `G:\app\packages\core` | Passed, 30 tests |
| `mvnw.cmd test` in `G:\schedule` | Passed, 5 tests, BUILD SUCCESS |

Remaining real-data input needed:

- To verify real electricity balance, add the user's dorm query parameters to
  local `.env.local`: `CAMPUS_TEST_ELEC_BUILDID` and
  `CAMPUS_TEST_ELEC_ROOMID`. `CAMPUS_TEST_ELEC_SYSID` and
  `CAMPUS_TEST_ELEC_AREAID` default to `1`.

## Mock Runtime Removal

User clarified that the refactor must not keep mock tests or mock data-source
paths. The project now treats only two product forms as valid:

- `localAndroid`: Android direct-school runtime.
- `selfHosted`: user-hosted backend/Web Console runtime.

Completed cleanup:

- Removed `CampusRuntimeMode.mock`.
- Removed mock/demo alias handling from app and background runtime resolution.
- Removed the login-page "experience mode" entry that saved placeholder
  credentials.
- Removed the `campus_adapters_mock` app dependency and Melos override.
- Regenerated `apps/campus_app/pubspec.lock`; `flutter pub get` reported that
  `campus_adapters_mock` is no longer depended on.
- Deleted the local `packages/adapters_mock` package.
- Updated `target.md` so future refactor work explicitly excludes Mock/Demo as
  a product form or test acceptance path.

Verification:

| Command | Result |
| --- | --- |
| `rg -n -i "mock\|demo\|fake\|stub" apps packages -g "*_test.dart" -g "*test*.dart" --glob "!**/ephemeral/**" --glob "!**/.plugin_symlinks/**" --glob "!**/.claude/**"` | No matches |
| `rg -n -i "campus_adapters_mock\|adapters_mock\|MockCampus\|CampusRuntimeMode\\.mock\|mock_user\|mock_pass\|体验模式\|Mock" apps packages -g "*.dart" -g "pubspec.yaml" -g "pubspec_overrides.yaml" -g "pubspec.lock"` | No matches |
| `rg -n -i "campus_adapters_mock\|adapters_mock" apps/campus_app/pubspec.lock apps/campus_app/pubspec.yaml apps/campus_app/pubspec_overrides.yaml` | No matches |
| `dart analyze .` in `G:\app` | Passed, no issues found |
| `flutter test` in `G:\app\apps\campus_app` | Passed, 4 tests |
| `flutter test` in `G:\app\packages\platform` | Passed, 12 tests |
| `flutter test` in `G:\app\packages\core` | Passed, 30 tests |
| `flutter test` in `G:\app\packages\data` | Passed: real schedule, grades, exams, and campus-card balance; real electricity test skipped because dorm parameters are not configured |
| `mvnw.cmd test` in `G:\schedule` | Passed, 5 tests, BUILD SUCCESS |

Legacy reuse baseline:

- The old backend at `G:\oldschedule` is the authoritative Java request-flow
  reference for CAS/session, schedule, grades, exams, electricity, campus card,
  leave, and Todo behavior.
- The front-end repository remote is
  `https://github.com/AAAAxuuuuu/cqjtu-campus-assistant.git`; use local git
  history/origin as the Flutter direct-school migration baseline.
- Refactor work should preserve and modularize the old request behavior instead
  of inventing new school-system protocols.

## Web Login Binding Refactor

Completed a small boundary cleanup after mock removal:

- Added `apps/campus_app/lib/features/auth/web_login_binder.dart`.
- `WebLoginBinder` now owns WebView login artifact binding for both valid
  runtime modes:
  - `localAndroid`: persists ticket/cookies/token locally and validates CAS
    ticket through `DirectSchoolCampusGateway.loginWithTicket`.
  - `selfHosted`: persists artifacts, refreshes the backend session, and
    injects ticket/cookies into the self-hosted backend session.
- `login_page.dart` now calls `webLoginBinderProvider` instead of duplicating
  ticket/cookie/session binding.
- `schedule_page.dart` now calls the same binder after WebView verification
  instead of manually calling `apiServiceProvider`, `sessionManagerProvider`,
  `loginWithTicket`, and `injectCookies` from the page layer.
- `utils/providers.dart` re-exports the binder for backward-compatible imports.

Verification after this refactor:

| Command | Result |
| --- | --- |
| `dart analyze .` in `G:\app` | Passed, no issues found |
| `flutter test` in `G:\app\apps\campus_app` | Passed, 4 tests |
| `flutter test` in `G:\app\packages\platform` | Passed, 12 tests |
| `flutter test` in `G:\app\packages\data` | Passed: real schedule, grades, exams, and campus-card balance; real electricity test skipped because dorm parameters are not configured |
| `flutter test` in `G:\app\packages\core` | Passed, 30 tests |
| `mvnw.cmd test` in `G:\schedule` | Passed, 5 tests, BUILD SUCCESS |
| mock-test scan | No matches |
| mock runtime/dependency scan | No matches |

Remaining app-layer backend/session coupling to reduce:

- `login_page.dart` still uses `SessionManager` for selfHosted schedule
  verification and error classification.
- `leave_apply_page.dart` still uses `apiServiceProvider` and
  `sessionManagerProvider`, but only inside the explicit selfHosted fallback.
