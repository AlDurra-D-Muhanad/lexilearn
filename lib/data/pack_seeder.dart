import 'package:lexilearn/domain/pack_codec.dart';
import 'package:sqflite/sqflite.dart';

import 'pack_dao.dart';

/// Copies the bundled asset into the database on first launch, and restores it
/// if the user deleted it. Never overwrites a user-imported pack that happens
/// to share the bundled pack key.
class PackSeeder {
  const PackSeeder(this._db);

  final Database _db;

  Future<bool> seedIfMissing(String bundledPackJson) async {
    final pack = PackCodec.decodePack(bundledPackJson);
    final dao = PackDao(_db);
    final existing = await dao.listPacks();
    final match = existing.where((summary) => summary.packKey == pack.packId);
    if (match.isNotEmpty) return false;
    await dao.insertPack(pack, isBundled: true, importedAt: DateTime.now().toUtc());
    return true;
  }
}