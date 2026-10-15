import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/vocab_repository.dart';
import 'ui/home_shell.dart';
import 'ui/theme/app_theme.dart';

/// The application root.
///
/// Takes an already-built [VocabRepository] rather than opening one itself, so
/// the widget tests can hand it an in-memory database and the composition root
/// in `main.dart` can hand it a real one. The only thing this widget decides is
/// chrome: the brand's two themes, the app title, and the app-wide text
/// direction.
class LexiLearnApp extends StatelessWidget {
  const LexiLearnApp({super.key, required this.repository});

  final VocabRepository repository;

  @override
  Widget build(BuildContext context) {
    return Provider<VocabRepository>.value(
      value: repository,
      child: MaterialApp(
        title: 'LexiLearn',
        // A development affordance. It would otherwise be baked into the
        // golden reference image and into store screenshots.
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        // Arabic-first RTL. Set once here rather than per screen, so a route
        // pushed later — the word detail view, a quiz, a backup sheet — inherits
        // it instead of having to remember. The bottom bar draws from the right
        // because of this line, which is where the brand artwork puts it.
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
        home: HomeShell(repository: repository),
      ),
    );
  }
}
