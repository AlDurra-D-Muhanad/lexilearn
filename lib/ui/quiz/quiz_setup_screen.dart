import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilearn/data/pack_dao.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/ui/home_shell.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';
import 'package:provider/provider.dart';

import 'quiz_controller.dart';
import 'quiz_screen.dart';

/// The chrome, in Arabic — see `quiz_screen.dart` for why.
const String _title = 'الاختبارات';
const String _packLabel = 'الحزمة التعليمية';
const String _choosePack = 'اختر الحزمة';
const String _noPacks = 'لا توجد حزم. استورد واحدة من تبويب المزيد.';
const String _lengthLabel = 'كم عدد الكلمات في الجلسة؟';
const String _lengthHint = '10';
const String _notANumber = 'أدخل رقمًا صحيحًا، مثل 10';
const String _overCap = 'الحد الأقصى 200 سؤال في الجلسة';
const String _startQuiz = 'ابدأ الاختبار';

/// A longer session than this is almost certainly a typo, and a session is
/// bounded anyway because the generator cycles a short pack.
const int _maxQuestions = 200;

/// The one-tap lengths the artwork's simplicity argues for, replacing the
/// original's `input()` prompt.
const List<int> _presets = <int>[10, 20, 50];

/// The height the pack picker occupies, reserved while it is still reading.
///
/// The theme's own form-field height, so the gap the form reserves while the
/// read is in flight is exactly the gap the dropdown fills when it lands and the
/// layout does not jump. Named rather than written as a literal at the one call
/// site that needs it while it is still in flight.
const double _pickerHeight = 56;

/// The brand's third destination: choosing a pack and a session length, then
/// running the quiz.
///
/// **The length is parsed, never re-prompted.** `Search.py` validated it with
/// `input()`, an `isdigit()` check and `return loop()` — a bad answer recursed,
/// so the third mistake blew the stack, and a `0` passed the digit check and
/// silently ran no questions at all. Here the text is parsed once and a wrong
/// answer says what is wrong.
///
/// Stateless, because everything it needs it is given: the pack key arrives from
/// `HomeShell` and changing pack is the shell's job. The two things that genuinely
/// are state — the length field and its error — live in [_QuizSetupForm], so the
/// widget this file exports keeps the constructor `HomeShell` was written
/// against.
class QuizSetupScreen extends StatelessWidget {
  const QuizSetupScreen({
    super.key,
    required this.packKey,
    this.packTitle = '',
    required this.onPackSelected,
  });

  /// The pack the quiz would be drawn from. Empty until the shell resolves it.
  final String packKey;

  /// The pack's **name**, for the pill above the pack picker.
  ///
  /// **The name, never the key.** The key is `dictionary_en_ar` — an
  /// identifier, and this pill is in front of the user. The shell resolves it
  /// with the pack list it reads at start-up and hands it down, so the pill is
  /// on screen the instant this destination mounts and never waits on a read.
  final String packTitle;

  /// Switches the active pack for the whole app, as on Home and More.
  final ValueChanged<String> onPackSelected;

  @override
  Widget build(BuildContext context) {
    // `ShellBackToHome` is this destination's share of the app's back button:
    // Android's back returns to `الرئيسية` rather than closing the app, which is
    // what the user asked for and what `HomeShell` documents. See that widget.
    return ShellBackToHome(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: const Text(_title),
          // The app's overflow menu, in the actions slot this bar already has and
          // was not using. One of four destinations that carry it — see
          // `AppOverflowMenu` for why the control is on all four and not only on
          // Home, and for the three pushed screens that deliberately do not.
          actions: const <Widget>[AppOverflowMenu()],
        ),
        body: SafeArea(
          child: _QuizSetupForm(
            packKey: packKey,
            packTitle: packTitle,
            onPackSelected: onPackSelected,
          ),
        ),
      ),
    );
  }
}

/// The pack picker, the length field, and the start button.
class _QuizSetupForm extends StatefulWidget {
  const _QuizSetupForm({
    required this.packKey,
    required this.packTitle,
    required this.onPackSelected,
  });

  final String packKey;

  /// The pack's display name, for the pill.
  final String packTitle;
  final ValueChanged<String> onPackSelected;

  @override
  State<_QuizSetupForm> createState() => _QuizSetupFormState();
}

class _QuizSetupFormState extends State<_QuizSetupForm> {
  final TextEditingController _length =
      TextEditingController(text: _lengthHint);

  String? _lengthError;

  /// The packs, read once. Held rather than rebuilt on every keystroke: the
  /// picker does not change while the user is typing a length.
  late final Future<List<PackSummary>> _packs =
      context.read<VocabRepository>().packs();

  @override
  void dispose() {
    _length.dispose();
    super.dispose();
  }

  /// Validates the length and, if it holds, pushes the quiz.
  ///
  /// The controller is created by the pushed route rather than handed to it, so
  /// `provider` has something above [QuizScreen] to find and disposing the route
  /// disposes the controller with it.
  void _start() {
    final text = _length.text.trim();
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 1) {
      setState(() => _lengthError = _notANumber);
      return;
    }
    if (parsed > _maxQuestions) {
      setState(() => _lengthError = _overCap);
      return;
    }
    setState(() => _lengthError = null);

    final repository = context.read<VocabRepository>();
    final packKey = widget.packKey;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<QuizController>(
          create: (_) => QuizController(
            repository: repository,
            packKey: packKey,
            questionCount: parsed,
          )..start(),
          child: const QuizScreen(),
        ),
      ),
    );
  }

  void _applyPreset(int value) => setState(() {
        _length.text = '$value';
        _lengthError = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.m),
      children: <Widget>[
        Text(_packLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.s),
        // Deliberately outside the `FutureBuilder` below: the pill is drawn from
        // the name the shell already resolved, so it must not wait on a read it
        // does not need. See [_PackPill].
        _PackPill(title: widget.packTitle),
        const SizedBox(height: AppSpacing.s),
        FutureBuilder<List<PackSummary>>(
          future: _packs,
          builder: (context, snapshot) {
            final packs = snapshot.data;
            if (packs == null) {
              // A reserved gap rather than a spinner. An indeterminate
              // `CircularProgressIndicator` schedules frames forever, and
              // `pumpAndSettle` therefore never settles while one is on screen:
              // `test/ui/home_shell_test.dart` and `test/ui/home_screen_test.dart`
              // both switch to this destination and `pumpAndSettle()` without
              // giving this read a `runAsync` turn, so a spinner here would hang
              // both of them rather than fail them. The gap is exactly the
              // dropdown's height, so the form does not jump when it lands.
              return const SizedBox(height: _pickerHeight);
            }
            if (packs.isEmpty) {
              return Text(
                _noPacks,
                style: theme.textTheme.bodyMedium,
              );
            }
            return DropdownButtonFormField<String>(
              // **Defensive, and currently redundant — do not read a green test
              // here as proof that it is load-bearing.** An earlier version of
              // this comment claimed that without the key `initialValue` is read
              // once and the field would show a stale pack. That is not what
              // happens: on Flutter 3.44.6,
              // `_DropdownButtonFormFieldState.didUpdateWidget`
              // (`dropdown.dart:2002-2007`) calls
              // `setValue(widget.initialValue)` when `initialValue` changes, so
              // the field already re-reads it. Deleting this key leaves all
              // 23 tests in `test/ui/quiz_screen_test.dart` green — measured,
              // not assumed. (23, not the 21 an earlier version of this comment
              // claimed: the file has grown since.)
              //
              // It is kept because the behaviour it leans on is an
              // implementation detail of one Flutter version rather than
              // documented contract, and because the failure it guards against
              // is a silent one: a field showing the previous pack while the
              // quiz draws from the next. If a future Flutter drops that
              // `didUpdateWidget` branch, this is what keeps the screen
              // correct. `test/ui/quiz_screen_test.dart` →
              // *the picker reports the pack the user chooses* proves the
              // *end* behaviour, not this mechanism.
              key: ValueKey<String>('quiz-pack-${widget.packKey}'),
              isExpanded: true,
              initialValue: packs.any((pack) => pack.packKey == widget.packKey)
                  ? widget.packKey
                  : packs.first.packKey,
              decoration: const InputDecoration(labelText: _choosePack),
              items: <DropdownMenuItem<String>>[
                for (final pack in packs)
                  DropdownMenuItem<String>(
                    value: pack.packKey,
                    child:
                        Text('${pack.title} (${pack.entryCount})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null && value != widget.packKey) {
                  widget.onPackSelected(value);
                }
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.l),
        Text(_lengthLabel, style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.s),
        TextField(
          controller: _length,
          keyboardType: TextInputType.number,
          // Digits only, so `int.tryParse` is the only parser this can meet and
          // a minus sign cannot be typed to sneak a negative length past the
          // check below.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            errorText: _lengthError,
            hintText: _lengthHint,
          ),
          onChanged: (_) {
            // Clears the error as soon as the field changes, so the message
            // never argues with a value that is being corrected.
            if (_lengthError != null) setState(() => _lengthError = null);
          },
          onSubmitted: (_) => _start(),
        ),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.s,
          children: <Widget>[
            for (final preset in _presets)
              ActionChip(label: Text('$preset'), onPressed: () => _applyPreset(preset)),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text(_startQuiz),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            // A pill, with the quiz screen's advance button and the result
            // screen's back button. These three are the app's full-width
            // actions, so they are the three the brand's stadium shape applies
            // to; the theme default is a 20px radius.
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

/// The active pack, named.
///
/// Drawn from the name `HomeShell` resolved and hands in, rather than from a read
/// of its own — so it is on screen the instant this destination mounts, and
/// cannot disagree with the pack the quiz would actually draw from. That is also
/// what `test/ui/home_shell_test.dart` asserts on every destination, and that
/// test switches here and `pumpAndSettle()`s without a `runAsync` turn for the
/// pack list below, so anything waiting on that read would never be found.
///
/// **The name, not the key.** A pack's key is an identifier — `dictionary_en_ar`
/// — and this pill is in front of the user. `HomeScreen` and `MoreScreen` draw
/// the same pill the same way.
class _PackPill extends StatelessWidget {
  const _PackPill({required this.title});

  /// The pack's display name, or the empty string while it is resolving.
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    // The name may be Arabic and it may be Latin, and the direction is the
    // paragraph's - the same rule the pack list applies to a pack's title.
    final isArabic = _writesArabic(title);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Text(
          // The em dash is the shell's start-up window rather than a missing
          // pack. A Latin pack name asks for Inter and LTR rather than the
          // ambient family; an Arabic one keeps the ambient family and the
          // app's direction.
          title.isEmpty ? '—' : title,
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          style: isArabic
              ? theme.textTheme.bodySmall?.copyWith(color: secondary)
              : AppText.latin
                  .copyWith(fontSize: AppText.caption, color: secondary),
        ),
      ),
    );
  }
}

/// Whether [value] carries an Arabic letter.
///
/// **The same block the app's other screens use** — U+0600 to U+06FF, plus the
/// Arabic Supplement and Extended-A blocks — so "is this Arabic?" is answered
/// the same way everywhere it is asked.
bool _writesArabic(String value) => value.runes.any(
      (rune) => (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0x0750 && rune <= 0x077F) ||
          (rune >= 0x08A0 && rune <= 0x08FF),
    );
