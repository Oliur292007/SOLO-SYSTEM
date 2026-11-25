# Shadow Learner — Release Readiness Checklist

This is a pre-release checklist. It does not authorize or trigger a release.

## 1. App identity and version

- [ ] Confirm the final display name: **Shadow Learner**.
- [ ] Keep Android application ID / namespace stable: `com.solosystem.shadowlearner`.
- [ ] Increment `version:` in `pubspec.yaml` for every public release (both version name and build number).
- [ ] Confirm the final launcher logo exists at `assets/branding/app_logo.png`; current CI downloads it from the configured Google Drive asset source.
- [ ] Confirm adaptive icon and splash-screen output on Android 12+ and older Android versions.

## 2. Signing and artifact security

- [ ] Create or identify the permanent Android upload/release keystore.
- [ ] Back up the keystore offline in at least two secure locations.
- [ ] Store only the Base64 keystore and passwords/alias in GitHub Actions repository secrets:
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- [ ] Never commit a keystore, passwords, service-role key, or private bot token.
- [ ] Verify the release APK is signed with the same permanent key used for previous installations before distributing updates.
- [ ] Verify APK signature and SHA-256 checksum after a release build.

## 3. Android permissions and user disclosure

Review the current manifest before distribution:
- Internet and network state.
- Notifications and boot receiver.
- Exact alarm scheduling.
- Usage access (`PACKAGE_USAGE_STATS`).
- Installed-app visibility (`QUERY_ALL_PACKAGES`).
- Accessibility service for Study Protection.
- Battery-optimization exemption request.

Explain in onboarding/privacy information why Usage Access and Accessibility access are needed, what app activity is processed, what is stored locally or sent to Supabase, and how users can disable the permissions. Do not describe Accessibility as a system-level uninstall blocker.

## 4. Backend and account readiness

- [ ] Verify Supabase production project, RLS policies, RPC grants, and required migrations.
- [ ] Verify Telegram bot webhook and registration/unlink flows.
- [ ] Verify public app config contains no private secrets or personal contact details.
- [ ] Verify code issuance, expiry, one-time use, and device binding.
- [ ] Confirm a support/contact route and incident response procedure.

## 5. Final validation

- [ ] Run Flutter analyze and the complete test suite.
- [ ] Test on a physical Android device after installing a candidate build.
- [ ] Verify fresh install, app update over the existing install, reboot, permission denial/re-enable, offline behavior, and cloud restore.
- [ ] Test Study Protection, app blocking, notifications, exact alarms, HP/MP, missions, penalty/Night Lock, Emergency Unlock, and protected-uninstall disclosures.
- [ ] Verify no test accounts, debug logs, placeholder values, or development endpoints remain.
- [ ] Record release version, commit SHA, APK SHA-256, and test evidence.

## Release authorization

The GitHub release workflow is manual-only and requires the `confirm_release` input to be explicitly set to `true`. A push to `main` must never publish a release. Do not dispatch the workflow with confirmation enabled until the owner explicitly requests a release.
