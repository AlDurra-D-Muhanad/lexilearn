import 'vocab_entry.dart';

/// Which word the Home screen shows as the word of the day.
///
/// A pure function of the entry list and the calendar day. That purity is the
/// entire reason the type exists: the Home screen rebuilds on every keystroke in
/// its search field, and a card that reshuffled itself on each rebuild would
/// show the user a different word every time they blinked. The day is an
/// *argument*, not a call to the clock, so a test pins a date instead of racing
/// midnight.
class WordOfTheDay {
  const WordOfTheDay._();

  static const int _millisecondsPerDay = 24 * 60 * 60 * 1000;

  /// The entry for [day], rotating through [entries].
  ///
  /// The index is the number of whole days since the Unix epoch modulo the pack
  /// length, so it is stable for a given date, advances by exactly one entry per
  /// day, and visits every entry once per cycle. Anything hashed off the wall
  /// clock instead would reshuffle on every rebuild, which is the defect this
  /// replaces.
  ///
  /// [day] is read in its own timezone — the user's calendar day, not UTC's.
  /// The `year`/`month`/`day` fields are taken as given rather than shifted,
  /// because a word of the day that changes at 02:00 local time is worse than one
  /// that changes in a place the user is not.
  ///
  /// Throws [ArgumentError] on an empty [entries]: there is no word to pick, and
  /// returning a placeholder here would put an empty card on the screen instead
  /// of the empty state the caller is meant to draw.
  static VocabEntry pick(List<VocabEntry> entries, DateTime day) {
    if (entries.isEmpty) {
      throw ArgumentError.value(
          entries, 'entries', 'cannot pick a word of the day from no entries');
    }
    final calendarDay = DateTime.utc(day.year, day.month, day.day);
    var index = calendarDay.millisecondsSinceEpoch ~/ _millisecondsPerDay;
    // `~/` truncates toward zero, so a pre-epoch date lands on a negative day
    // number and a negative remainder. Fold it back into range rather than
    // letting a negative index throw.
    index %= entries.length;
    if (index < 0) index += entries.length;
    return entries[index];
  }
}
