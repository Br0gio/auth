import 'dart:async';
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import "package:photos/utils/multipart_upload_util.dart";
import 'package:sqflite/sqflite.dart';

class UploadLocksDB {
  static const _databaseName = "ente.upload_locks.db";
  static const _databaseVersion = 1;

  static const _table = (
    table: "upload_locks",
    columnID: "id",
    columnOwner: "owner",
    columnTime: "time",
  );

  static const _trackUploadTable = (
    table: "track_uploads",
    columnID: "id",
    columnLocalID: "local_id",
    columnFileHash: "file_hash",
    columnEncryptedFilePath: "encrypted_file_path",
    columnEncryptedFileSize: "encrypted_file_size",
    columnFileKey: "file_key",
    columnObjectKey: "object_key",
    columnCompleteUrl: "complete_url",
    columnCompletionStatus: "completion_status",
    columnPartSize: "part_size",
  );

  static const _partsTable = (
    table: "upload_parts",
    columnObjectKey: "object_key",
    columnPartNumber: "part_number",
    columnPartUrl: "part_url",
    columnPartStatus: "part_status",
  );

  UploadLocksDB._privateConstructor();
  static final UploadLocksDB instance = UploadLocksDB._privateConstructor();

  static Future<Database>? _dbFuture;
  Future<Database> get database async {
    _dbFuture ??= _initDatabase();
    return _dbFuture!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute(
      '''
                CREATE TABLE ${_table.table} (
                  ${_table.columnID} TEXT PRIMARY KEY NOT NULL,
                  ${_table.columnOwner} TEXT NOT NULL,
                 ${_table.columnTime} TEXT NOT NULL
                )
                ''',
    );
    await db.execute(
      '''
                CREATE TABLE ${_trackUploadTable.table} (
                  ${_trackUploadTable.columnID} TEXT PRIMARY KEY NOT NULL,
                  ${_trackUploadTable.columnLocalID} TEXT NOT NULL,
                  ${_trackUploadTable.columnFileHash} TEXT NOT NULL UNIQUE,
                  ${_trackUploadTable.columnEncryptedFilePath} TEXT NOT NULL,
                  ${_trackUploadTable.columnEncryptedFileSize} INTEGER NOT NULL,
                  ${_trackUploadTable.columnFileKey} TEXT NOT NULL,
                  ${_trackUploadTable.columnObjectKey} TEXT NOT NULL,
                  ${_trackUploadTable.columnCompleteUrl} TEXT NOT NULL,
                  ${_trackUploadTable.columnCompletionStatus} TEXT NOT NULL,
                  ${_trackUploadTable.columnPartSize} INTEGER NOT NULL
                )
                ''',
    );
    await db.execute(
      '''
                CREATE TABLE ${_partsTable.table} (
                  ${_partsTable.columnObjectKey} TEXT PRIMARY KEY NOT NULL REFERENCES ${_trackUploadTable.table}(${_trackUploadTable.columnObjectKey}) ON DELETE CASCADE,
                  ${_partsTable.columnPartNumber} INTEGER NOT NULL,
                  ${_partsTable.columnPartUrl} TEXT NOT NULL,
                  ${_partsTable.columnPartStatus} TEXT NOT NULL
                )
                ''',
    );
  }

  Future<void> clearTable() async {
    final db = await instance.database;
    await db.delete(_table.table);
  }

  Future<void> clearTrackTable() async {
    final db = await instance.database;
    await db.delete(_trackUploadTable.table);
  }

  Future<void> acquireLock(String id, String owner, int time) async {
    final db = await instance.database;
    final row = <String, dynamic>{};
    row[_table.columnID] = id;
    row[_table.columnOwner] = owner;
    row[_table.columnTime] = time;
    await db.insert(
      _table.table,
      row,
      conflictAlgorithm: ConflictAlgorithm.fail,
    );
  }

  Future<bool> isLocked(String id, String owner) async {
    final db = await instance.database;
    final rows = await db.query(
      _table.table,
      where: '${_table.columnID} = ? AND ${_table.columnOwner} = ?',
      whereArgs: [id, owner],
    );
    return rows.length == 1;
  }

  Future<int> releaseLock(String id, String owner) async {
    final db = await instance.database;
    return db.delete(
      _table.table,
      where: '${_table.columnID} = ? AND ${_table.columnOwner} = ?',
      whereArgs: [id, owner],
    );
  }

  Future<int> releaseLocksAcquiredByOwnerBefore(String owner, int time) async {
    final db = await instance.database;
    return db.delete(
      _table.table,
      where: '${_table.columnOwner} = ? AND ${_table.columnTime} < ?',
      whereArgs: [owner, time],
    );
  }

  Future<int> releaseAllLocksAcquiredBefore(int time) async {
    final db = await instance.database;
    return db.delete(
      _table.table,
      where: '${_table.columnTime} < ?',
      whereArgs: [time],
    );
  }

  // For multipart download tracking
  Future<bool> doesExists(String localId, String hash) async {
    final db = await instance.database;
    final rows = await db.query(_trackUploadTable.table);
    return rows.isNotEmpty;
  }

  Future<MultipartUploadURLs> getCachedLinks(
    String localId,
    String fileHash,
  ) async {
    final db = await instance.database;
    final rows = await db.query(
      _trackUploadTable.table,
      where:
          '${_trackUploadTable.columnLocalID} = ? AND ${_trackUploadTable.columnFileHash} = ?',
      whereArgs: [localId, fileHash],
    );
    if (rows.isEmpty) {
      throw Exception("No cached links found for $localId and $fileHash");
    }
    final row = rows.first;
    final objectKey = row[_trackUploadTable.columnObjectKey] as String;
    final partsStatus = await db.query(
      _partsTable.table,
      where: '${_partsTable.columnObjectKey} = ?',
      whereArgs: [objectKey],
    );

    final List<bool> partUploadStatus = [];
    final List<String> partsURLs = List.generate(
      partsStatus.length,
      (index) => "",
    );

    for (final part in partsStatus) {
      final partNumber = part[_partsTable.columnPartNumber] as int;
      final partUrl = part[_partsTable.columnPartUrl] as String;
      final partStatus = part[_partsTable.columnPartStatus] as String;
      if (partStatus == "uploaded") {
        partsURLs[partNumber] = partUrl;
        partUploadStatus.add(partStatus == "uploaded");
      }
    }
    final urls = MultipartUploadURLs(
      objectKey: objectKey,
      completeURL: row[_trackUploadTable.columnCompleteUrl] as String,
      partsURLs: partsURLs,
      partUploadStatus: partUploadStatus,
    );

    return urls;
  }
}
