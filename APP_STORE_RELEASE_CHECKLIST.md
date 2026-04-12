# NightBites App Store Release Checklist

Use this checklist before submitting a build to App Review.

## Code and product

- [x] Guest student entry supported.
- [x] Demo owner entry hidden in release builds (`#if DEBUG`).
- [x] Order linkage migrated to stable `truckID` with legacy fallback.
- [x] Telemetry events wired for auth/checkout/order lifecycle.
- [x] Support/legal links surfaced in app profile screen.
- [x] Digital payments gated off by default until fully integrated.
- [x] Firebase + Sentry SDK packages added to app target.
- [x] Firebase app startup init added (guarded by config plist presence).

## Must complete before submission

- [ ] Replace placeholder legal URLs with live hosted pages:
  - Info.plist: `PRIVACY_POLICY_URL`
  - Info.plist: `TERMS_URL`
- [ ] Confirm support email is monitored:
  - Info.plist: `SUPPORT_EMAIL`
- [ ] Add `GoogleService-Info.plist` for production Firebase project and verify `AppReleaseConfig.enableFirebaseAnalytics`.
- [ ] Set production Sentry DSN:
  - Info.plist: `SENTRY_DSN`
- [ ] Configure Google sign-in:
  - Info.plist: `ENABLE_GOOGLE_SIGN_IN`
  - Info.plist: `GOOGLE_OAUTH_REDIRECT_URL`
  - Supabase provider + redirect URL must match app config.
- [ ] Configure payments backend + Stripe:
  - Info.plist: `STRIPE_PUBLISHABLE_KEY`
  - Info.plist: `STRIPE_MERCHANT_IDENTIFIER`
  - Info.plist: `PAYMENTS_API_BASE_URL`
- [ ] Implement and verify real payment integration before enabling digital payments:
  - Info.plist: `ENABLE_DIGITAL_PAYMENTS = YES` only after QA.
- [ ] Remove any test/demo accounts from App Review-facing copy if not needed.

## QA pass

- [ ] Smoke test student flow: browse -> cart -> checkout -> order appears in history.
- [ ] Smoke test owner flow: queue actions, status transitions, prep time controls.
- [ ] Network failure tests: airplane mode and poor connectivity behavior.
- [ ] Device QA: latest iPhone + one older device simulator.
- [ ] Regression test persisted orders across app relaunch.

## App Store Connect / policy

- [ ] Privacy Nutrition Labels completed in App Store Connect.
- [ ] App Privacy Policy URL added in App Store Connect.
- [ ] Age rating and content rights completed.
- [ ] Screenshots, description, and keywords finalized.
- [ ] App Review notes added (including how to access primary flows).

## Release command (local)

```bash
xcodebuild -project NightBites.xcodeproj -scheme NightBites -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```
