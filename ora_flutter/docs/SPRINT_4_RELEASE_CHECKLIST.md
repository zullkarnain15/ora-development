# Sprint 4 Release Checklist

Date: 2026-08-14

## Engineering gates

- [x] Flutter static analysis passes.
- [x] Automated unit/widget suite passes.
- [x] Durable queue and schema v1-to-v4 migration are tested.
- [x] Pure Flutter route viewer has no map/network dependency.
- [ ] Full Android physical duration and route matrix passes.
- [ ] Production backend idempotency is evidenced.
- [ ] iOS release build passes on macOS.
- [ ] Android production signing replaces debug signing.
- [ ] iOS distribution certificate/profile and TestFlight upload pass.

## Permissions and platform declarations

- [x] Android declares coarse/fine location, location foreground service, notification, and internet permissions.
- [x] Android tracking service is non-exported and declares `foregroundServiceType="location"`.
- [x] iOS contains foreground and always/background location purpose strings plus location background mode.
- [ ] Google Play foreground-service declaration and video/demo evidence reviewed.
- [ ] Google Play Data safety form reviewed and approved.
- [ ] App Store privacy nutrition labels and location justification reviewed and approved.

## Privacy and retention decisions

- [x] Session and local activities are owner-isolated in application code.
- [x] Routes stay local; only finalized activity summaries use the existing backend contract.
- [x] Diagnostic logging avoids raw coordinates.
- [ ] Product owner defines retention/deletion policy for local GPS points, run events, queue ACK metadata, and session tokens.
- [ ] Privacy policy explains precise/background location, offline persistence, sync, retention, and account/logout behavior.

## Quality and accessibility

- [x] Existing automated text-scaling checks pass.
- [x] Empty and large route rendering are bounded.
- [ ] TalkBack/VoiceOver labels and focus order verified physically.
- [ ] Memory, frame time, and battery delta measured during a representative long run.
- [ ] Low-power and vendor battery-optimization guidance verified.

This checklist must remain open until every unchecked release gate has evidence.
