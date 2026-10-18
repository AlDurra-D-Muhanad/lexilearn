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

### A line number is a claim about a file

**The rule.** A `file.dart:123` citation deserves the same suspicion as a claim about a mechanism.
Open the file and look.

**Why.** In Task 13's second fix round, **two of the citations in the review brief itself were wrong**:
`icon_button.dart:308` is `this.focusNode`, not an elevation line (the real one is `:1112-1113`), and
"one pack executes all three delete-loop sites" held only for sites 1–4 — site 5 needed two packs too.
The implementer had already found three wrong citations of its own. **Four out of seven citations in one
round were wrong, from two different authors.**

A wrong citation is more damaging than a missing one: it looks verified, so the next reader does not
open the file either.

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

**Baseline: 17.27 MiB / 18.11 MB** (Task 16, with the launcher icon in). An earlier figure of 17.26 MB did not reproduce -- the same command on the unmodified tree measured 17.45 MiB. **Use the Task 16 report's numbers.** Measured with
`flutter build apk --release --target-platform android-arm64 --analyze-size`, against a 20 MB budget.

| | MB |
|---|---|
| `libflutter.so` | 11.05 |
| `libapp.so` (the app's own AOT code) | 4.94 |
| fonts + MaterialIcons (tree-shaken to 4.9 KB from 1.61 MB) | ~1.05 |
| `classes.dex` | 0.27 compressed / **0.58 uncompressed** |

> **Correction, and it was mine — TWICE.** An earlier version of this table claimed R8 took classes.dex
> from 8.53 MB to 271 KB. That was false. I then "corrected" it to say R8 had never run, so the baseline
> was measured without it. **That second correction was also false.** R8 **was** already running: Flutter's
> Gradle plugin sets isMinifyEnabled and isShrinkResources on the release build type itself
> (FlutterPlugin.kt:215-227), and lutter_command.dart:988 says the shrink flag "has no effect".
> The proof is that outputs/mapping/release/usage.txt exists, and only R8 writes it.
>
> Like-for-like on the identical command: **18,295,222 -> 18,305,778 B = +10,556 B (+0.06%)**, with
> classes.dex **271 KB compressed in both**. The whole delta is the launcher icon's es/ PNGs.
>
> **Two corrections in a row, both wrong, and the second was more confident than the first** — it carried
> a file path as evidence and still did not open it. **A correction is not evidence. Only a measurement is.**

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

---

## 13. Never run an unbounded command

**The rule.** Every long command goes through `tool/run-bounded.ps1`:

```powershell
powershell -ExecutionPolicy Bypass -File tool\run-bounded.ps1 -Cmd "flutter test" -TimeoutSeconds 900 -Label suite
```

`0` = success · `N` = the command's own failure code · `124` = timed out and the tree was killed.

**Why this exists.** Four distinct hangs, only one of which is a failing test:

1. a test awaiting a real future inside a fake-async zone — `flutter_test`'s `testWidgets` defaults
   to **`Timeout.none`**, and `flutter test --timeout` *explicitly does not apply to the suite-loading
   timeout*. A test-level bound does not reliably catch this.
2. an orphaned `flutter_tester` / `dart` still holding
   `build\native_assets\windows\sqlite3.dll`, so the **next** run blocks on startup.
3. Gradle or the Flutter tool waiting on something that will never arrive.
4. a toolchain flake with no cause at all — e.g.
   `Unable to connect to flutter_tester process: WebSocketException`.

A shell-level deadline catches all four. `flutter test --timeout` catches, at best, one.

**The wrapper kills the process TREE, not `cmd.exe`.** Killing only the parent leaves `dart`,
`flutter_tester` and `java` running, and those are exactly what keep `sqlite3.dll` locked. Verified:
after a forced timeout, `cmd`, `ping`, `flutter_tester` and `dart` all return to 0.

**A timeout is never flattened into the failure path.** Exit `124` is reserved for a timeout; a real
failure keeps its own code. A wrapper that reports every outcome as "failed" teaches you to ignore it.

**Deadlines, and how they were chosen.** Every one of these was **measured**, and the first draft of
this table was not — it guessed `flutter analyze` at ~10 s from an early run. It is actually **~105 s**.
A deadline set from that guess would have failed on a healthy machine. This is §1 aimed at this file.

| Command | Deadline | Measured | Headroom |
|---|---|---|---|
| `flutter analyze` | 300 s | **105 s** | 2.9x |
| `flutter test` (one file) | 300 s | ~12 s | 25x |
| `flutter test` (whole suite) | 900 s | ~84 s | 10.7x |
| `flutter build apk --release` | 1800 s | 491 s | 3.7x |

Below 3x headroom, treat a timeout as a real signal and read the log. Above 10x, a timeout means
something is actually stuck.

### The lock message you will eventually see

```
Flutter failed to delete file at "build\native_assets\windows\sqlite3.dll".
```

This is hang mode 2. **Something still holds it** — almost always a `dart` or `flutter_tester` left
alive by an earlier run, or by a concurrent one. Check `Get-Process dart,flutter_tester` **before**
killing anything: if another task is legitimately running, the fix is to wait, not to reap.

### When a command times out, read the log before re-running

`run-bounded.ps1` prints the last 40 lines on timeout — that is *where it stopped*, which is the whole
diagnosis. Re-running first destroys the only evidence.

---

## 14. Subagent dispatch fails — retry, but verify first

Dispatch has failed **seven times** in this project: rate limit ×5, `ECONNRESET`, `ENOTFOUND
opencode.ai`, `WebSocketException`. **Every failure was transport. None was correctness.**

**The protocol:**

1. **Verify before retrying.** `git log -1`, `git status --short`, and check whether the report file
   exists. A failed dispatch may still have written files. Never assume "it failed, so nothing
   happened" — twice a dead subagent left analyzer-clean, uncommitted work.
2. **Re-send the SAME brief, not a narrower one.** Narrowing loses the review's value entirely, and the
   implementer needs the same context you had.
3. **Diagnose what you can before re-dispatching.** The rate-limited implementer for Task 13 left six
   compile errors from *one* bad `const`. Reading the codepoints and the real constructor signatures
   turned a re-dispatch into a two-line handoff.
4. **After three failures, change the mechanism, not the brief** — split the task, or take the remaining
   work inline yourself.

**Always hand over a diagnosis when there is one.** A subagent that inherits "these six errors" burns a
cycle rediscovering them. A subagent handed "line 31 is illegal because `DateTime.utc` is a factory, and
lines 88 and 94 are collateral" starts working immediately.

---

## 15. Rate-limit failures leave work behind; the toolchain lies

Three failure kinds, tracked separately under §9. One more, observed on this project:

**A subagent that dies mid-task leaves partial work that may be analyzer-clean but is untested.** The
right response is to check what exists, run the analyser yourself, and hand over a diagnosis — not to
restart. Restarting throws away correct work and costs a full dispatch.

`docs/privacy-policy.md` will say the app has no internet permission. **Verified from the built
release artefact:** the merged `AndroidManifest.xml` inside the release APK contains no `INTERNET`,
no `ACCESS_NETWORK_STATE`, no `READ_EXTERNAL_STORAGE`, no `MANAGE_EXTERNAL_STORAGE`.

`android/app/src/main/AndroidManifest.xml` declares **no permissions at all**. `INTERNET` appears only
in the `debug/` and `profile/` manifests, which Flutter adds for the debugger and which never ship.

Re-verify after any dependency change.