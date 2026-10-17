# Engineering standards

Everything here was learned the hard way in this repository. Each rule names the incident that
produced it, because a rule without an incident gets "simplified" away by the next person who does
not know what it is protecting.

This file governs `lib/`, `test/`, `tool/` and any Dart you add. Brand rules live separately in
[`style-direction.md`](style-direction.md).

---

## 1. A claim in prose is not evidence

**The rule.** If you write "this is safe because X", either run X and paste the output, or do not
write the claim.

**Why.** Task 11 shipped a report stating that two constants were preserved through a refactor. The
arithmetic had actually changed them: the progress track went `6 → 4` and the option padding
`14 → 12`, silently shrinking every quiz option row from 54.0px to 50.0px. The full suite was green
in both states. Only a reviewer doing the arithmetic caught it.

In the same task, a test comment claimed a `ValueKey` was load-bearing. Deleting it left **all 21
tests green** — Flutter 3.44.6's `_DropdownButtonFormFieldState.didUpdateWidget` calls
`setValue(widget.initialValue)`, so the key was already redundant.

**A comment cannot fail.** That is not a reason to write fewer comments; it is a reason to make every
comment's *subject* a test.

### Self-inflicted, twice in one round

Task 12's implementer found three unevaluated claims in Task 11, then made three more in its own
report — including a claim that the dark theme test "demands 5 `AppSurface`s" when it asserts
per-label ancestors. It later found that a doc comment quoted `setState(() => _confirming = false)`
while instructing the reader to grep for that string, so its own recommended check returned three
hits instead of one.

**Derive prose from what you ran.** Not from what you expect.

---

## 2. Assert tree state after a pop, never the return value

**The rule.**

```dart
// WRONG - fails on correct code
expect(await tester.binding.handlePopRoute(), isFalse);

// RIGHT
expect(find.byType(MoreScreen), findsOneWidget);
```

**Why.** Traced through this SDK's source:

```
binding.dart:1113   handlePopRoute()  -> observers' didPopRoute()
app.dart:1607       WidgetsApp.didPopRoute()  -> return navigator.maybePop()
navigator.dart:5546 case RoutePopDisposition.doNotPop:
                      lastEntry.route.onPopInvokedWithResult(false, result);
                      return true;                       // <-- true, despite the block
routes.dart:2035    popDisposition -> doNotPop when a PopEntry.canPopNotifier is false
pop_scope.dart:190  sets that notifier to widget.canPop
```

`maybePop` returns `false` **only** when there is no present route or the pop bubbles. A deliberate
block counts as *handled*. The same chain runs on a real device (`binding.dart:1307`, the Android
`popRoute` channel), so this is not a test-harness artifact.

---

## 3. A DAO call made without the transaction's handle waits forever

**The rule.** Every DAO call inside `db.transaction((txn) => ...)` receives `executor: txn`, and
every DAO that can be called from one accepts `{DatabaseExecutor? executor}` defaulting to
`(executor ?? _db)`.

**Why.** A call made without the handle does not fail fast. **It waits** — no exception, no log line, no
timeout message you wrote. Read out of `sqflite_common-2.5.14`, because guessing this is how the wrong
version of this section got here in the first place:

- `database_mixin.dart:894-902` — `transaction()` wraps its whole body in `txnWriteSynchronized`, which
  takes `_rawLock`, a **Dart-side non-reentrant `Lock` declared at `:496`.
- `database_mixin.dart:549-592` — `txnSynchronized` runs straight through when handed the transaction and
  otherwise queues on `_rawLock.synchronized(…)`. Its own comment reads *"synchronized call to the
  database / not re-entrant"*.
- After `utils.lockWarningDuration` — **10 seconds**, `constant.dart:174` — `utils.dart:43-49` prints
  `Warning database has been locked … Make sure you always use the transaction object for database
  operations during a transaction`.
- `sqflite_common_ffi-2.4.4/lib/src/sqflite_ffi_impl.dart:275-315` queues them on the FFI side too.
  `handleTransactionId`, whose doc comment is *"If a transaction is in progress and we are not in it, queue
  for later"*.

**It is the same `Database` object, not a second connection, and none of this is about a SQLite file
lock.** `database_mixin.dart:423` opens with `BEGIN IMMEDIATE`, not a deferred `BEGIN`, and **the block
is not data-dependent**: the first call inside the transaction blocks whether it reads or writes and
whether the table is empty. Measured — dropping `executor: txn` from the very first delete-loop call
with one pack installed and zero rows still fails, which contradicts the "deferred transaction" story
this section used to tell.

**Seven calls in `importBackupJson`**, not two. The two Task 7 knew about happened to have the
parameter already. `PackDao` had **no `executor` on any method at all** and holds its own `_db`.

**Because the failure mode is a hang, it needs a guard-timeout test:**

```dart
expectLater(repository.importBackupJson(json).timeout(Duration(seconds: 5)), completes);
```

Without it, a regression is invisible to CI.

**The guard only covers a call that is *reached*.** Three of the seven are iterated over what the backup
file contains, and a file with no progress rows and no sessions never enters those loop bodies — the
guard still passes at 5/7 with two of the arguments deleted, and nothing says so. So the fixture is part
of the guard: seed a device with at least one pack, a file with at least one pack, **at least one
progress row and at least one session**, then drop one argument at a time and check that each of the
seven goes red.

---

## 4. Encoding: diagnose from codepoints, never from the screen

**The rules.**

- Never round-trip source through PowerShell's `Get-Content` / `Set-Content`. They add a BOM and use
  the console codepage. Use `[System.IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)` and
  `WriteAllText`.
- Never `.Replace()` with a non-ASCII needle.
- **Never conclude a file is corrupt from rendered output.** Print codepoints.

**Why.** This project has had three scares. The third was self-inflicted: a plan line read
``Type `???` in Search`` and looked like corrupted Arabic. Printing codepoints gave
`U+062F U+0641 U+0646` — **دفن**, intact. The corruption was the terminal.

A `U+FFFD` count of 0 had already answered it. It was disbelieved because the screen looked certain.

Also note: `git show <path> | Out-String` re-encodes and miscounts Arabic. Use `ReadAllText`, or
`git cat-file blob` via `cmd` redirection.

---

## 5. Fake-async traps: real futures never complete in `testWidgets`

**The rule.** Use the shared helpers in [`test/helpers/test_env.dart`](../test/helpers/test_env.dart).
Never write a private copy of the dance.

| Helper | Use |
|---|---|
| `pumpShell(tester, repository)` | reach any `HomeShell` destination |
| `settleDatabase(tester)` | one real turn of the event loop |
| `commitAndSettle(tester)` | a write followed by that turn |
| `readOutsideFakeAsync<T>(...)` | read a value produced by a real future |
| `useAPhone(tester)` | the 360x780 viewport |

**Why.** `HomeShell` reads the active pack from SQLite in `initState`. Inside `testWidgets` the
zone is fake-async, so a real future never completes — **and it does not fail, it hangs for the full
ten minutes.**

Two subtleties that cost real time:

- **Two adjacent `runAsync` calls wait for nothing.** The destination's read is only *issued* during a
  rebuild, so it has not started when the second wait begins. There must be a `pump()` between them.
- **Opening a database, or awaiting a controller method, inside a `testWidgets` body** hangs the same
  way. `setUpAll(() async { await TestHarness.create(...) })` and
  `unawaited(controller.answer(i))` followed by a `runAsync` turn are both worked examples in the file.

**Do not run two suites concurrently.** They contend for
`build/native_assets/windows/sqlite3.dll`, and the DB-settle wait was measured at 2 turns under load
against a 3-turn budget. A second suite *is* the load that was measured.

---

## 6. Cards go through `AppSurface`, never a bare `Card`

**The rule.** Every card is an `AppSurface`. `AppSurface` carries the brand hairline plus
`AppShadows.light`, because `CardThemeData` has no shadow field. It also takes an optional `fill`,
which **removes the hairline in the same rule** — there is no second parameter.

**Why.** A bare `Card` renders a hard black keyline in this rasteriser. It measured **29,111 pure
`#000000` pixels** baked into a golden that looked fine in a thumbnail.

Same for `elevation`: M3's default of 1 reintroduces the keyline. `ElevatedButton`,
`FloatingActionButton` and `Menu` all need explicit `elevation: 0`.

### Verify by sampling pixels

```powershell
powershell -ExecutionPolicy Bypass -File tool\golden_census.ps1
```

It asserts `#000000` == 0, `#1D1B20` == 0 and `#1F2937` > 0, and prints the token table for every
shipped PNG.

**A guard that cannot fail is not a guard.** It was proven by feeding it three canaries: a 1px black
keyline (661 px), a `#1D1B20` block (13200 px), and a fully magenta fill (mode unidentified). Each
exits 1.

Never judge a colour by looking at a picture. A thumbnail hid 29,111 black pixels.

---

## 7. M3 paints a filled input's outline from `onSurfaceVariant`, not from your `border`

**The rule.** The theme sets `enabledBorder`, `focusedBorder` and `disabledBorder` on
`inputDecorationTheme`. Do not override borders per screen.

**Why.** A plain `TextField` under `AppTheme.light()` with **zero local decoration** rasterised a
`#6B7280` outline and **zero** `#E5E7EB` anywhere. `InputDecorator.decoration.enabledBorder` came
back `null`, proving Material synthesises the border inside the decorator.

**Do not change `onSurfaceVariant`.** It is correctly the secondary-text role and is pinned by
`test/design/app_theme_test.dart`; recolouring it recolours every muted string in the app.

`test/design/input_outline_test.dart` guards this with a plain `TextField` and no local decoration —
the only shape that would catch it.

---

## 8. Refactors must be value-preserving, and measured

**The rule.** When replacing a literal with a token expression, **measure before and after** and show
both numbers.

**Why.** See §1. `AppSpacing.m - AppSpacing.xs` is 12, not 14. `AppSpacing.s - AppSpacing.xs` is 4,
not 6. Both were shipped green.

**Corollary:** do not write the arithmetic in a comment unless you evaluated it. One comment said
"54 is the row's text plus 2 × 14" — which is 24 + 28 = **52**. The missing 2px was the 1px
`Border.all`. The pinned 54.0 was right; the stated derivation was not.

---

## 9. Three kinds of failure, tracked separately

| Kind | Signature | Whose fault |
|---|---|---|
| **Weak test** | changes when the bug is introduced | the test's |
| **Flaky test** | breaks under load, passes alone | the test's design |
| **Toolchain failure** | breaks for no reason at all | nobody's |

A toolchain failure looks like this and is not an assertion:

```
Unable to connect to flutter_tester process: WebSocketException
```

**Do not quietly re-run until green.** Verify the file is byte-identical to `HEAD`, note when it was
last touched, re-run to confirm, and say so in the report. One clean run after a toolchain flake is
not evidence, and the next reviewer deserves to know the failure predates the change.

---

## 10. Design review is part of done

**The rule.** A screen task ends with a committed golden in light **and** dark, and the census run
over it. Report the design decisions you inferred, and mark them as inferences.

**Why.** `docs/design/brand-reference.png` is the authority. Task 12's accuracy ring has **no
counterpart in the artwork** — the mock's only proportion indicator is a *linear* bar. The ring's
design therefore came from the spec, and saying so was required.

**Why the goldens are reference images, not byte goldens:** the font rasteriser differs per platform,
so `golden_test.dart` is `skip:`-ed. They also bake a local timestamp (`DateTime.utc(...).toLocal()`),
so a UTC machine renders `12:00` where a UTC+3 box rendered `15:00`. The census is immune — it reads
colours, not glyphs.

---

## 11. Release size: measure, never estimate

**Verified figure: 17.26 MB** for
`flutter build apk --release --target-platform android-arm64 --analyze-size`, against a 20 MB budget.

| | MB |
|---|---|
| `libflutter.so` | 11.05 |
| `libapp.so` (the app's own AOT code) | 4.94 |
| fonts + MaterialIcons (tree-shaken to 4.9 KB from 1.61 MB) | ~1.05 |
| `classes.dex` (R8: 8.53 MB → 271 KB) | 0.27 |

**A prediction of 21-28 MB from itemised arithmetic was wrong by ~20%**, in three ways: `libapp.so`
was never given its own row, tree-shaking was not credited, and R8 was underestimated 4×.

**A debug APK is not a download-size proxy.** Of the 152.98 MB debug figure, ~92 MB is
`kernel_blob.bin` (67 MB), `isolate_snapshot_data` (10.6 MB) and a debug-only Vulkan validation layer
(14.5 MB) — none of which any user downloads. Record the **arm64 per-ABI** number or none.

If `lib/arm64-v8a/libflutter.so` is absent, the build is debug or profile and the figure is
meaningless.

---

## 12. Offline is a legal claim, not a feature description

`docs/privacy-policy.md` will say the app has no internet permission. **Verified from the built
release artefact:** the merged `AndroidManifest.xml` inside the release APK contains no `INTERNET`,
no `ACCESS_NETWORK_STATE`, no `READ_EXTERNAL_STORAGE`, no `MANAGE_EXTERNAL_STORAGE`.

`android/app/src/main/AndroidManifest.xml` declares **no permissions at all**. `INTERNET` appears only
in the `debug/` and `profile/` manifests, which Flutter adds for the debugger and which never ship.

Re-verify after any dependency change.