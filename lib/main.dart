import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lexilearn/app.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/pack_codec.dart';
import 'package:lexilearn/ui/dictionary/dictionary_controller.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_theme.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;

/// The composition root. The only place that knows about the asset bundle, the
/// documents directory, and SQLite all at once.
///
/// `LexiLearnApp` takes a ready repository so this stays testable; the wiring
/// that a widget test cannot exercise — opening the database at the app's
/// documents path, seeding the bundled pack, and starting the dictionary's
/// copy — lives here and nowhere else.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const bundledPackAsset = 'assets/packs/english_ar_v1.json';
  try {
    final documents = await getApplicationDocumentsDirectory();
    final database = await openAppDatabase(
      factory: databaseFactory,
      path: p.join(documents.path, 'lexilearn.db'),
    );
    final repository = VocabRepository(database: database);
    // Safe on every start: seeding decodes first and returns false when the
    // pack is already installed, so a corrupt asset cannot overwrite anything
    // and a good one cannot duplicate anything.
    await repository.seedBundledPack(await rootBundle.loadString(bundledPackAsset));
    // **The dictionary's own row in `packs`.** It carries no entries — the
    // dictionary's 31,600 words live in a read-only file of their own and must
    // never reach a backup — but the row has to exist, because
    // `favorites.pack_key` is a foreign key onto `packs(pack_key)` and a
    // favourite for a dictionary word would otherwise be rejected.
    await repository.ensureDictionaryPack();

    // **The dictionary's controller, built here and started by the app.**
    //
    // The copy is 26 MB and it must not be on the start-up path, so nothing
    // awaits it: `LexiLearnApp` fires `start()` off its own `initState` and
    // the app opens, navigates and shows the home screen while the copy
    // runs. The home screen shows the progress.
    final dictionary = DictionaryController(
      repository: repository,
      loadAsset: rootBundle.load,
      loadMorphology: rootBundle.loadString,
      targetPath: p.join(documents.path, 'dictionary', 'en_ar.db'),
      databaseFactory: databaseFactory,
    );
    runApp(LexiLearnApp(repository: repository, dictionary: dictionary));
  } on PackDecodeException catch (error) {
    _fatal('The bundled vocabulary file is broken: ${error.message}');
  } on FileSystemException catch (error) {
    _fatal('Could not open local storage: ${error.message}');
  }
}

/// The screen shown when the app cannot start.
///
/// A person reads this, so it is a sentence and not a stack trace, inside the
/// brand's own surface rather than Flutter's red error page — the app is
/// already themed, and a launch failure should not read as a crash.
void _fatal(String message) {
  // The theme is built here rather than read from a `BuildContext` because this
  // subtree is handed straight to `runApp` — there is no ancestor to read from.
  final theme = AppTheme.light();
  runApp(
    MaterialApp(
      title: 'LexiLearn',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: AppSurface(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // `theme.colorScheme.error`, which for this `AppTheme.light()`
                    // resolves to `AppColors.errorLight` — pinned by
                    // `test/design/app_theme_test.dart` → *the colour scheme is the
                    // brand palette*. **Value-preserving, and that is the point of
                    // the change rather than a side effect of it**: the fatal
                    // screen hard-codes `AppTheme.light()` because it is handed
                    // straight to `runApp` with no ancestor to read a theme from,
                    // so this subtree can never be dark. Reading the light token
                    // through the theme it was built with means the next person to
                    // give this subtree a `themeMode` does not silently leave a
                    // dark-mode error in a light-mode screen — which is precisely
                    // the defect `quiz_screen.dart` shipped for fifteen
                    // review-clean tasks.
                    Icon(
                      Icons.error_outline,
                      size: 40,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Text(
                      'تعذّر بدء التطبيق',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textSecondaryLight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
