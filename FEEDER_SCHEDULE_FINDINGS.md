# Add Schedule / Toggle → "not authenticated"

## Diagnosis (verified, not a guess)
That string is thrown in exactly one place — `functions/notifications/feeder_schedule_mutation.js:60`:
```js
if (!uid) throw new ScheduleMutationError("unauthenticated", "Sign in before changing schedules.");
```
`uid = context.auth.uid || verifyIdToken(data.idToken).uid`. So the deployed function saw **no auth
context AND no usable idToken**. Both add and toggle share this callable → both fail together, which
matches the symptom. The validation path is fine: driven with a stub `firebase-admin`, valid input passes
end-to-end (`ADD → {"scheduleId":"gen1"}`, `TOGGLE off/on` correct); only genuine rejections fire
(`already-exists`, `permission-denied`, `failed-precondition`).

## The fix already exists in main — you just haven't shipped it
`git log -S"idToken"` on BOTH sides returns one commit only: `531431b` (Sep 11 10:18AM).
- client `lib/services/feeder_service.dart:836` → `.call({...payload, 'idToken': idToken})`
- callable `functions/notifications/feeder_schedules.js` → `admin.auth().verifyIdToken(data.idToken)` fallback

Reproduced old vs new (same payload, auth header stripped):
```
LUMA (eaea9b9): FAIL -> [unauthenticated] "Sign in before changing schedules."
BAGO (531431b): PASS {"scheduleId":"gen1"}
```
So: the Cloud Function and/or the installed APK predates `531431b`.

## Steps
1. `firebase deploy --only functions:notifications`   (deploy + verify: `firebase functions:list`)
2. Full app rebuild/reinstall — hot restart does NOT pick up Dart changes.
3. Sign out → sign in (fresh token), retry add + toggle.

## If still unauthenticated after 1+2
Cloud Logging for `mutateFeederSchedule rejected: …` (the fallback logs booleans only, no PII):
- `missing auth context {hasAuth:false, hadIdToken:false}` → client is still stale → redo step 2.
- `rejected: invalid idToken {error:…}` → the token itself was rejected. Real causes: expired/revoked
  session (fix = step 3), project mismatch (verified OK here: `firebase_options.dart` `projectId:
  craycare-8436c`, `authDomain: craycare-8436c.firebaseapp.com`), or `verifyIdToken` audience mismatch.

## Secondary defects (NOT this error — unrelated to auth)
1. `ADD` with blank amount persists `grams: null` (`scheduleFields` → `grams: data.grams == null ? null : …`).
   App and ESP both silently fall back to 20 g, but Firestore stores `null` while rules for
   `feeder_commands` require `grams is number` → Feed Now with blank amount is denied, schedule add is not.
   Fix: resolve the default server-side (`grams: grams ?? 20`) or omit the key.
2. `TOGGLE`/`EDIT` validate the **stored** doc, not what the app displays:
   `FAIL TOGGLE ON, legacy doc walang days -> [invalid-argument] "Select at least one repeat day."`
   `overlaps()` already tolerates missing `days` (`?? "1111111"`), but the enable path re-runs
   `scheduleFields(previous)` with no fallback → such a row can never be toggled on or edited.
3. Both readers order by `timeValue`, which hides docs lacking it, while the ESP still runs them via its
   `time`/`ampm` fallback → invisible-but-feeding rows the user cannot delete.
   `feeder_service.dart:402` `.orderBy('timeValue')` / `main.cpp:2262 … "timeValue", "", false`.
4. Raw exception text leaks to the snackbar: `_toggleSchedule` interpolates `$error` on a `StateError`
   → user sees "Bad state: …" (`_addSchedule` strips only `'Exception: '`). All non-`ScheduleMutationError`
   failures are flattened to `internal` "Could not save the schedule…", so logs are the only signal.
5. `npm test` in `functions/notifications`: 15 tests pass — zero cover `mutateSchedule`. Nothing caught this.
