import 'package:flutter/material.dart';
import 'package:lexilearn/data/vocab_repository.dart';
import 'package:lexilearn/design/design_tokens.dart';
import 'package:lexilearn/domain/custom_dictionary.dart';
import 'package:lexilearn/ui/settings/app_overflow_menu.dart';
import 'package:lexilearn/ui/theme/app_surface.dart';
import 'package:lexilearn/ui/theme/app_verdict_colors.dart';
import 'package:provider/provider.dart';

/// The chrome, in Arabic.
const String _title = 'إنشاء قاموسك الخاص';
const String _subtitle = 'أضف كلماتك ومعانيها كما تريد';
const String _wordLabel = 'الكلمة';
const String _wordHelper = 'أدخل الكلمة التي تريد إضافتها إلى قاموسك';
const String _wordHint = 'مثال: البرمجة';
const String _meaningLabel = 'المعنى';
const String _meaningHelper = 'أدخل معنى الكلمة كما تريده';
const String _meaningHint =
    'مثال: هي عملية كتابة التعليمات للأجهزة من أجل تنفيذ مهام معينة.';
const String _saveLabel = 'حفظ الكلمة';
const String _backTooltip = 'رجوع';

/// The two refusals the screen makes itself, before the repository is asked.
///
/// The repository refuses the same two states and its sentences are the same;
/// saying them here as well is what puts each message **inline, under the field
/// that is missing** instead of in a sentence at the foot of the card.
const String _wordRequired = 'اكتب الكلمة أولاً.';
const String _meaningRequired = 'اكتب معنى الكلمة أولاً.';
const String _saveFailed = 'تعذّر حفظ الكلمة. حاول مرة أخرى.';

/// The success dialog.
const String _success = 'تم إضافة الكلمة بنجاح';
const String _done = 'تم';

/// The fields' keys, so a test can type into the right one without counting
/// `TextField`s in tree order.
const Key _wordFieldKey = ValueKey<String>('custom-word-field');
const Key _meaningFieldKey = ValueKey<String>('custom-meaning-field');

/// The screen the landing screen's `إضافة كلمة` card opens.
///
/// **It does not pop on save.** The user's brief is explicit: after `تم` the
/// screen stays where it is and both fields are cleared, so a student adding a
/// curriculum's words can type the next pair without leaving and coming back.
/// The success dialog is therefore awaited, and the clearing happens when it
/// closes.
///
/// **The overflow menu is the drawing's, and it sits at the top-left.** In this
/// right-to-left app that is the `AppBar`'s actions side, so `AppOverflowMenu`
/// is the same control the four bar destinations carry and not a second menu.
class AddCustomWordScreen extends StatefulWidget {
  const AddCustomWordScreen({super.key});

  @override
  State<AddCustomWordScreen> createState() => _AddCustomWordScreenState();
}

class _AddCustomWordScreenState extends State<AddCustomWordScreen> {
  final TextEditingController _word = TextEditingController();
  final TextEditingController _meaning = TextEditingController();

  /// The inline refusals, one per field, plus one for a sentence the repository
  /// produced (a duplicate, or a length the field's `maxLength` should have made
  /// unreachable).
  String? _wordError;
  String? _meaningError;
  String? _formError;

  /// True while a write is in flight, so a second tap cannot start a second
  /// one — and so the button says it is working rather than looking ignored.
  bool _saving = false;

  @override
  void dispose() {
    _word.dispose();
    _meaning.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;

    final word = _word.text.trim();
    final meaning = _meaning.text.trim();
    final wordMissing = word.isEmpty;
    final meaningMissing = meaning.isEmpty;

    setState(() {
      _wordError = wordMissing ? _wordRequired : null;
      _meaningError = meaningMissing ? _meaningRequired : null;
      _formError = null;
    });
    // **No write is attempted when a field is empty.** The refusal has to be a
    // refusal, not a write the repository then rejects: the test asserts the
    // dictionary still has zero words.
    if (wordMissing || meaningMissing) return;

    setState(() => _saving = true);
    try {
      await context.read<VocabRepository>().addCustomWord(
        term: word,
        meaning: meaning,
      );
    } on CustomDictionaryException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // The repository's own Arabic sentence, shown rather than replaced.
        // A duplicate is the one the user will meet in practice.
        _formError = error.message;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = _saveFailed;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);
    FocusScope.of(context).unfocus();

    await _showSuccess();

    // **Still on this screen, and empty.** The brief says the user stays after
    // `تم` and the fields are cleared so the next word can be typed.
    if (!mounted) return;
    _word.clear();
    _meaning.clear();
    setState(() {
      _wordError = null;
      _meaningError = null;
      _formError = null;
    });
  }

  /// The green check, the sentence and one button.
  ///
  /// Not `barrierDismissible`: the drawing gives this dialog exactly one control,
  /// and a tap outside is not one of the ways the brief describes leaving it.
  Future<void> _showSuccess() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final isDark = theme.brightness == Brightness.dark;
      return Dialog(
        elevation: 0,
        backgroundColor: isDark
            ? AppColors.surfaceDark
            : AppColors.surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.check_circle_rounded,
                size: 56,
                // The app's green ink for this brightness — the same value
                // the quiz's right-answer tick and the overflow menu's
                // check use, through the verdict extension rather than a
                // second spelling of it.
                color: AppVerdictColors.of(dialogContext).correctBorder,
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                _success,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.l),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: const Text(_done),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final error = isDark ? AppColors.errorDark : AppColors.errorLight;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _Header(),
              const SizedBox(height: AppSpacing.s),
              Text(
                _subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: secondary),
              ),
              const SizedBox(height: AppSpacing.l),
              AppSurface(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _FieldLabel(label: _wordLabel, badge: const _WordBadge()),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _wordHelper,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    TextField(
                      key: _wordFieldKey,
                      controller: _word,
                      maxLength: customWordMaxLength,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: _wordHint,
                        hintTextDirection: TextDirection.rtl,
                        errorText: _wordError,
                      ),
                      // **No counter on the word field.** The drawing shows one
                      // only under the meaning, and `maxLength` still enforces
                      // the bound.
                      buildCounter:
                          (
                            BuildContext context, {
                            required int currentLength,
                            required bool isFocused,
                            required int? maxLength,
                          }) => null,
                      onChanged: (_) {
                        if (_wordError == null && _formError == null) return;
                        setState(() {
                          _wordError = null;
                          _formError = null;
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.l),
                    _FieldLabel(
                      label: _meaningLabel,
                      badge: const _MeaningBadge(),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _meaningHelper,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    TextField(
                      key: _meaningFieldKey,
                      controller: _meaning,
                      // **Three lines, not five.** The drawing's meaning field is
                      // 220 px in an 852-px-wide mock — about 93 dp, which is
                      // three 24-dp lines plus the field's padding. Five lines
                      // made it a 152-dp capsule on the phone, and the field, not
                      // the words, became the largest thing on the screen.
                      // `maxLines` still lets a long meaning grow.
                      minLines: 3,
                      maxLines: 8,
                      maxLength: customMeaningMaxLength,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: _meaningHint,
                        hintTextDirection: TextDirection.rtl,
                        errorText: _meaningError,
                      ),
                      // **The drawing's `0/500`, and the same number
                      // `maxLength` enforces.** The counter is LTR because it
                      // is a numeral pair, not an Arabic sentence.
                      buildCounter:
                          (
                            BuildContext context, {
                            required int currentLength,
                            required bool isFocused,
                            required int? maxLength,
                          }) => Text(
                            '$currentLength/$maxLength',
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: secondary,
                            ),
                          ),
                      onChanged: (_) {
                        if (_meaningError == null && _formError == null) {
                          return;
                        }
                        setState(() {
                          _meaningError = null;
                          _formError = null;
                        });
                      },
                    ),
                    if (_formError != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.m),
                      Text(
                        _formError!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text(_saveLabel),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The back chevron, the menu, and the screen's title.
///
/// **The title sits against the start edge — the right in this app — and is
/// scaled down rather than cut off.** The drawing prints `إنشاء قاموسك الخاص`
/// in full; at `headlineSmall` it is a little wider than the space the back
/// control and the menu leave on a 360-dp phone, and an ellipsis there reads as
/// a broken heading. `FittedBox` shrinks it by the few pixels needed and leaves
/// it alone when it fits.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 64, end: 64),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _title,
                  maxLines: 1,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: _backTooltip,
              onPressed: () => _maybePop(context),
              icon: const Icon(Icons.chevron_right_rounded, size: 32),
            ),
          ),
          // The drawing's ellipsis is on the physical left, which is the end
          // side in this app. The menu brings its own 16 px edge inset, so the
          // glyph lands where Home's does.
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppOverflowMenu(),
          ),
        ],
      ),
    );
  }
}

void _maybePop(BuildContext context) => Navigator.of(context).maybePop();

/// The label row: the badge first, then the Arabic label, as the drawing's
/// right-to-left reading order has them.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.badge});

  final String label;
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        badge,
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

/// The `Aa` badge: the Latin face, on the brand's icon disc.
class _WordBadge extends StatelessWidget {
  const _WordBadge();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _BadgeDisc(
      child: Text(
        'Aa',
        textDirection: TextDirection.ltr,
        style: AppText.latin.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.accentInk(isDark),
        ),
      ),
    );
  }
}

/// The note badge beside «المعنى».
class _MeaningBadge extends StatelessWidget {
  const _MeaningBadge();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return _BadgeDisc(
      child: Icon(
        Icons.sticky_note_2_outlined,
        size: 20,
        color: AppColors.accentInk(isDark),
      ),
    );
  }
}

/// The disc both field badges share, so they are one size and one ramp.
class _BadgeDisc extends StatelessWidget {
  const _BadgeDisc({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: AppGradients.iconBadge(isDark),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppColors.outlineDark : AppColors.outlineLight,
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}
