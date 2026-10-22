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

/// **The line that says how long a session over the selected pack may be.**
///
/// The user's own words: «لا تسمح بعمل اختبار بأكثر من الكلمات الموجودة بحزمة
/// المفضلة» — do not allow a quiz with more questions than the words in the
/// favourites pack. With one saved word and a request for a hundred questions,
/// the same word was asked a hundred times.
///
/// **So the cap is the pack's size, and this line is what says so.** A cap that
/// is applied without being shown is a cap the user cannot see, and a field
/// that quietly answers 1 when 1 was typed is a field lying about what it was
/// asked. The line is **always** on the screen, under the length field, and it
/// names the number the session will actually be.
String _packCap(int questions) => 'الحد الأقصى $questions سؤال في هذه الحزمة';

/// **The line that says the request was cut down to the pack's size.**
///
/// Said when the number is cut, and said in the app's own words rather than by
/// silently showing a different number in the field.
String _cappedToPack(int questions) =>
    'تم تقليص عدد الأسئلة إلى $questions، وهو عدد كلمات الحزمة';

/// **The line that says the pack has nothing in it.**
const String _emptyPack = 'هذه الحزمة فارغة، فلا يمكن أن يكون فيها اختبار';

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

  /// **The length the user has asked for, as a number.**
  ///
  /// Held so the line under the field can say what will happen to it: a
  /// request above the pack's size is not refused, it is **cut down**, and the
  /// screen says so before the user presses the button rather than after.
  ///
  /// Null when the field does not hold a number at all, which is the one case
  /// the field's own error speaks for.
  int? _requested;

  /// The packs, read once. Held rather than rebuilt on every keystroke: the
  /// picker does not change while the user is typing a length.
  late final Future<List<PackSummary>> _packs =
      context.read<VocabRepository>().packs();

  /// The pack the session would be drawn from, once the list has answered.
  ///
  /// **The active pack, and it is the one the picker shows.** The picker's
  /// `initialValue` is the active key when the list holds it and the list's
  /// first entry otherwise, so this is the same rule — one pack, named once,
  /// and the cap below is the cap of the pack the quiz would really use.
  ///
  /// **Held rather than read again in [_start].** The list is read once, in
  /// `initState`, and a second read would be a second answer to the same
  /// question — and a read inside a button handler is a read inside a
  /// fake-async zone in a test, which is the trap
  /// `docs/engineering-standards.md` §5 is about. So the builder keeps it, and
  /// [_start] uses what the builder already knows.
  PackSummary? _selected;

  /// The pack the session would be drawn from, out of [packs].
  ///
  /// **The active pack, and it is the one the picker shows.** The picker's
  /// `initialValue` is the active key when the list holds it and the list's
  /// first entry otherwise, so this is the same rule — one pack, named once,
  /// and the cap is the cap of the pack the quiz would really use.
  ///
  /// Null while the list has not answered, and null when it has answered with
  /// nothing, because a list with no packs in it has no pack to cap.
  PackSummary? _selectedOf(List<PackSummary>? packs) {
    if (packs == null || packs.isEmpty) return null;
    for (final pack in packs) {
      if (pack.packKey == widget.packKey) return pack;
    }
    return packs.first;
  }

  /// The longest session this pack can carry.
  ///
  /// **The pack's own size, and not the app's cap alone.** A session longer
  /// than the pack is a session that asks the same word again and again: the
  /// user reported «سيتم اعادة و تكرار نفس الكلمه بالاختبار» — the same word
  /// asked over and over — with one saved word and a hundred questions asked
  /// for.
  ///
  /// The app's own cap still applies, and it is the smaller of the two that
  /// wins: a hundred-question session over the dictionary is a hundred
  /// questions, and a hundred-question session over a one-word pack is one
  /// question.
  int _maxFor(PackSummary pack) =>
      pack.entryCount < _maxQuestions ? pack.entryCount : _maxQuestions;

  /// **The line under the length field.**
  ///
  /// Three sentences, and which one it is depends on what the user has typed:
  ///
  /// * the request is over the ceiling — **what will happen to it**, which is
  ///   the one the user has to read before pressing the button;
  /// * the pack is smaller than the app's ceiling — the pack's own ceiling;
  /// * the pack is at least as big as the app's ceiling — the app's ceiling.
  String _capLine(PackSummary pack) {
    final cap = _maxFor(pack);
    final requested = _requested;
    if (requested != null && requested > cap) return _cappedToPack(cap);
    return cap < _maxQuestions ? _packCap(cap) : _overCap;
  }

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
  ///
  /// **The length is cut down to the pack's size, and the screen says so.**
  /// The line under the field always names the cap (see [_packCap]), so the
  /// user is told before they press the button rather than after; and the
  /// field itself is corrected to the number the session will really be, so
  /// the field never says one thing and the quiz does another.
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
    final pack = _selected;
    final cap = pack == null ? _maxQuestions : _maxFor(pack);
    if (cap < 1) {
      setState(() => _lengthError = _emptyPack);
      return;
    }
    final count = parsed < cap ? parsed : cap;
    if (count != parsed) {
      // The field is corrected to the number the session will be, so the two
      // never disagree.
      _length.text = '$count';
    }
    setState(() {
      _lengthError = null;
      _requested = count;
    });

    final repository = context.read<VocabRepository>();
    final packKey = widget.packKey;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<QuizController>(
          create: (_) => QuizController(
            repository: repository,
            packKey: packKey,
            questionCount: count,
          )..start(),
          child: const QuizScreen(),
        ),
      ),
    );
  }

  void _applyPreset(int value) => setState(() {
        _length.text = '$value';
        _lengthError = null;
        _requested = value;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

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
        // **Everything that depends on the pack list is built inside this
        // builder**, and that is the whole reason it is here rather than
        // wrapped around the picker alone.
        //
        // The line under the length field quotes **the selected pack's size**,
        // and a widget built outside this builder would be built before the
        // list has answered — so it would be built with no pack and would never
        // be built again. The picker and the line are one thing, and this
        // builder is where they are drawn.
        FutureBuilder<List<PackSummary>>(
          future: _packs,
          builder: (context, snapshot) {
            final packs = snapshot.data;
            // **The pack the session would be drawn from.** The same rule the
            // picker's `initialValue` uses, so the cap the screen quotes is
            // the cap of the pack the picker is showing. It is kept on the
            // state as well, because [_start] needs it and the list is read
            // once.
            final selected = _selectedOf(packs);
            _selected = selected;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (packs == null)
                  // A reserved gap rather than a spinner. An indeterminate
                  // `CircularProgressIndicator` schedules frames forever, and
                  // `pumpAndSettle` therefore never settles while one is on
                  // screen: `test/ui/home_shell_test.dart` and
                  // `test/ui/home_screen_test.dart` both switch to this
                  // destination and `pumpAndSettle()` without giving this
                  // read a `runAsync` turn, so a spinner here would hang both
                  // of them rather than fail them. The gap is exactly the
                  // dropdown's height, so the form does not jump when it
                  // lands.
                  const SizedBox(height: _pickerHeight)
                else if (packs.isEmpty)
                  Text(
                    _noPacks,
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  _picker(packs),
                const SizedBox(height: AppSpacing.l),
                Text(_lengthLabel, style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.s),
                TextField(
                  controller: _length,
                  keyboardType: TextInputType.number,
                  // Digits only, so `int.tryParse` is the only parser this can
                  // meet and a minus sign cannot be typed to sneak a negative
                  // length past the check below.
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    errorText: _lengthError,
                    hintText: _lengthHint,
                  ),
                  onChanged: (value) {
                    // **The number in the field is read here**, because the
                    // line under it says what will happen to that number: a
                    // request above the pack's size is cut down, and the
                    // screen says so while the user is still typing.
                    final requested = int.tryParse(value.trim());
                    if (requested == _requested && _lengthError == null) return;
                    setState(() {
                      _requested = requested;
                      // Clears the error as soon as the field changes, so the
                      // message never argues with a value that is being
                      // corrected.
                      _lengthError = null;
                    });
                  },
                  onSubmitted: (_) => _start(),
                ),
                const SizedBox(height: AppSpacing.xs),
                // **The cap, said out loud.**
                //
                // The user's own words: «لا تسمح بعمل اختبار بأكثر من الكلمات
                // الموجودة بحزمة المفضلة» — do not allow a quiz with more
                // questions than the words in the favourites pack. A cap that
                // is applied without being shown is a cap the user cannot
                // see, and a field that quietly answers one question when a
                // hundred were asked for is a field lying about what it was
                // asked.
                //
                // **It is a line of its own and not the field's
                // `helperText`,** because Material hides the helper when the
                // field carries an error — and the line has to be there when
                // the field is *wrong*, which is exactly when the user needs
                // to read it.
                //
                // **And it says what will happen to the number in the field**,
                // not only what the ceiling is: a request above the ceiling is
                // not refused, it is cut down, and the line says so while the
                // user is still typing.
                if (selected != null) ...<Widget>[
                  Text(
                    _capLine(selected),
                    style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: AppSpacing.s),
                ] else
                  const SizedBox(height: AppSpacing.s),
                Wrap(
                  spacing: AppSpacing.s,
                  children: <Widget>[
                    for (final preset in _presets)
                      ActionChip(
                        label: Text('$preset'),
                        onPressed: () => _applyPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.l),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text(_startQuiz),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                    // A pill, with the quiz screen's advance button and the
                    // result screen's back button. These three are the app's
                    // full-width actions, so they are the three the brand's
                    // stadium shape applies to; the theme default is a 20px
                    // radius.
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The pack chooser.
  ///
  /// **Its own method, so the builder above reads as the page it is.**
  Widget _picker(List<PackSummary> packs) {
    return DropdownButtonFormField<String>(
      // **Defensive, and currently redundant — do not read a green test here as
      // proof that it is load-bearing.** An earlier version of this comment
      // claimed that without the key `initialValue` is read once and the field
      // would show a stale pack. That is not what happens: on Flutter 3.44.6,
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
      // *end behaviour*, not this mechanism.
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
            // **The name and nothing else.** The number beside it was
            // the user's complaint: «ازل الرقم من جانب اسم الحزمة» —
            // remove the number from beside the pack's name. The size
            // is still on the screen, in the line under the length
            // field, where it is the *cap* rather than a stray number
            // on a name.
            child: Text(pack.title, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (value) {
        if (value != null && value != widget.packKey) {
          widget.onPackSelected(value);
        }
      },
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
