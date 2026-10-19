import 'package:url_launcher/url_launcher.dart' as launcher;

/// Hands [url] to whatever app on the device claims it, and answers whether
/// anything did.
///
/// **This typedef is the whole reason no test needs a phone.** It is the same
/// shape as `PickJsonFile` in `packs_controller.dart`, for the same reason and
/// with the same reasoning written down: the awkward environment sits behind one
/// named seam, and every test past it is plain Dart. A test injects
/// `(uri) async { fired = uri; return true; }` and then asserts on the `Uri`
/// itself — which is the *entire* payload of the Android intent, read out of
/// `url_launcher_android-6.3.33/android/src/main/java/io/flutter/plugins/
/// urllauncher/UrlLauncher.java:87-90`:
///
/// ```java
/// Intent launchIntent =
///     new Intent(Intent.ACTION_VIEW)
///         .setData(Uri.parse(url))
///         .putExtra(Browser.EXTRA_HEADERS, extractBundle(headers));
/// ```
///
/// So `Uri` in, `ACTION_VIEW` out, and there is nothing between the two that a
/// test could otherwise be checking. [openWithUrlLauncher] is what the app
/// installs; a test installs something else.
///
/// **Why `url_launcher` and not a `MethodChannel` this project writes itself.**
/// The decision, with what it cost and what was checked:
///
/// * **No permission, measured rather than assumed.** `docs/engineering-standards.md`
///   §12 says the release APK's merged manifest carries no `INTERNET`. The plugin's
///   own manifest —
///   `url_launcher_android-6.3.33/android/src/main/AndroidManifest.xml` — declares
///   **no `<uses-permission>` element at all**, only a non-exported
///   `WebViewActivity`; and this app's `android/app/src/main/AndroidManifest.xml`
///   declares none either. The manifest merger can only union what a dependency
///   contributes, so nothing is contributed. **The limit of that measurement is
///   stated rather than hidden: the final merged release manifest was NOT
///   re-extracted from a built APK, because this round was not permitted to run
///   `flutter build`. §12's own instruction is "re-verify after any dependency
///   change", and this is that instruction not yet discharged.**
/// * **It works on every platform this Flutter app can be built for.** A
///   hand-written `ACTION_VIEW` channel would be Kotlin in `MainActivity` — the
///   first platform code this project has ever had — and would silently do
///   nothing on desktop or web, where `flutter test` actually runs.
/// * **It answers "did anything take it?"**, which `startActivity` does not
///   unless you wrap the `ActivityNotFoundException` yourself. That answer is
///   what lets the menu say a sentence instead of swallowing the tap.
///
/// **What it costs.** Four packages instead of zero, and the umbrella pulls in
/// `url_launcher_ios`, `_macos`, `_web`, `_linux` and `_windows`, none of which
/// an Android build registers. The size budget has 2.73 MB of headroom against a
/// 20 MB cap, and `url_launcher` carries no native library — it is a platform
/// channel and some Java.
///
/// **Why [LaunchMode.platformDefault] and not `externalApplication`.**
/// `externalApplication` sets `requireNonBrowser: true`, which on API 30+ adds
/// `Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER` (`UrlLauncher.java:91-93`). On a
/// phone with no Telegram installed that makes the intent fail rather than fall
/// back to a browser, so the link would be dead for exactly the users least able
/// to fix it. `platformDefault` fires the plain `ACTION_VIEW` and lets Android's
/// own `resolveActivity` decide — Telegram wins where it is the registered
/// handler, the browser wins otherwise, and `t.me` then offers to hand over.
/// Which of the two the user's phone picks cannot be measured from here, so it
/// is not claimed.
typedef OpenExternalUrl = Future<bool> Function(Uri url);

/// The real launcher: `url_launcher`, in its plain `ACTION_VIEW` mode.
Future<bool> openWithUrlLauncher(Uri url) =>
    launcher.launchUrl(url, mode: launcher.LaunchMode.platformDefault);

/// Where the overflow menu's Telegram entry goes.
///
/// **`https://t.me/MUHANAD_D`, exactly.** `t.me` rather than `telegram.me`
/// because it is the shorter of the two and both resolve; the handle is the
/// user's own and is written once here so the menu, the about screen and the
/// test all quote one string rather than three that agree today.
///
/// The deep link `tg://resolve?domain=MUHANAD_D` is **not** used, for the same
/// reason `platformDefault` is not: it resolves on a device with Telegram and
/// nowhere else, where the `https://` form degrades to a web page that offers to
/// open the app.
final Uri telegramContactUri = Uri.parse('https://t.me/MUHANAD_D');