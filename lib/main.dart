import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:lexilearn/app.dart';
import 'package:lexilearn/data/database.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/pack_codec.dart';
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
/// documents path and seeding the bundled pack — lives here and nowhere else.
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
    runApp(LexiLearnApp(repository: repository));
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
                    const Icon(
                      Icons.error_outline,
                      size: 40,
                      color: AppColors.errorLight,
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
