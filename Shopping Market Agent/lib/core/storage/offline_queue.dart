import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// SQLite-backed offline action queue. When the agent is offline, every action
/// (mark picked, weight diff, substitute, etc.) is queued here. On reconnect,
/// the connectivity listener drains the queue in order.
class OfflineQueue {
  static Database? _db;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'agent_offline.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action_type TEXT NOT NULL,
            method TEXT NOT NULL,
            path TEXT NOT NULL,
            payload TEXT,
            created_at INTEGER NOT NULL,
            retries INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
  }

  static Future<int> enqueue({
    required String actionType,
    required String method,
    required String path,
    Map<String, dynamic>? payload,
  }) async {
    if (_db == null) await init();
    return _db!.insert('actions', {
      'action_type': actionType,
      'method': method,
      'path': path,
      'payload': payload != null ? jsonEncode(payload) : null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<Map<String, dynamic>>> pending() async {
    if (_db == null) await init();
    return _db!.query('actions', orderBy: 'created_at ASC');
  }

  static Future<void> markDone(int id) async {
    if (_db == null) return;
    await _db!.delete('actions', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> bumpRetry(int id) async {
    if (_db == null) return;
    await _db!.rawUpdate('UPDATE actions SET retries = retries + 1 WHERE id = ?', [id]);
  }

  static Future<int> pendingCount() async {
    if (_db == null) await init();
    final r = await _db!.rawQuery('SELECT COUNT(*) AS c FROM actions');
    return (r.first['c'] as int?) ?? 0;
  }
}
