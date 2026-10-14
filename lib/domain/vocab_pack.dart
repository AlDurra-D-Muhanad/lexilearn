import 'vocab_entry.dart';

/// A named, self-contained collection of entries plus enough metadata to render
/// it without any other context.
///
/// Immutable: every field is final and set in the constructor.
class VocabPack {
  const VocabPack({
    required this.schemaVersion,
    required this.packId,
    required this.title,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.entries,
  });

  /// Bump only when the on-disk shape changes, and handle the old version in
  /// `PackCodec`. This is what makes future backup files loadable.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String packId;
  final String title;
  final String sourceLanguage;
  final String targetLanguage;
  final List<VocabEntry> entries;

  int get entryCount => entries.length;
  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'packId': packId,
        'title': title,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'entries': <Map<String, Object?>>[
          for (final entry in entries) entry.toJson(),
        ],
      };

  static VocabPack fromJson(Map<String, Object?> json) {
    final rawEntries = json['entries'] as List<dynamic>;
    return VocabPack(
      schemaVersion: (json['schemaVersion'] as num).toInt(),
      packId: json['packId'] as String,
      title: json['title'] as String,
      sourceLanguage: (json['sourceLanguage'] as String?) ?? 'en',
      targetLanguage: (json['targetLanguage'] as String?) ?? 'ar',
      entries: <VocabEntry>[
        for (final raw in rawEntries)
          VocabEntry.fromJson((raw as Map<dynamic, dynamic>).cast<String, Object?>()),
      ],
    );
  }
}
