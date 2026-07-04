import 'package:sqflite_common/sqflite.dart' show openDatabase;
import 'package:sqflite_common/sqlite_api.dart';

/// Opens a SpatiaLite-enabled database at [path].
///
/// This wraps [openDatabase] so that `SELECT InitSpatialMetaData(1)` (the
/// "fast" metadata initialization, recommended for SpatiaLite >= 4.x) runs
/// first, before any user-supplied [OpenDatabaseOptions.onConfigure],
/// [OpenDatabaseOptions.onCreate] or [OpenDatabaseOptions.onUpgrade]. This
/// ordering matters: `AddGeometryColumn`/`CreateSpatialIndex` (see
/// `addGeometryColumnSql`/`createSpatialIndexSql`) depend on the
/// `geometry_columns` metadata tables that `InitSpatialMetaData` creates, so
/// they must never run before it.
///
/// Only relevant on platforms whose native SQLite engine understands
/// SpatiaLite SQL functions (currently Android). On other platforms this
/// still opens successfully as a plain database, but `InitSpatialMetaData`
/// and any other SpatiaLite call will fail.
Future<Database> openSpatialDatabase(
  String path, {
  OpenDatabaseOptions? options,
}) {
  final userOnConfigure = options?.onConfigure;
  final wrappedOptions = OpenDatabaseOptions(
    version: options?.version,
    onConfigure: (db) async {
      // `SELECT InitSpatialMetaData(1)` is syntactically a SELECT statement,
      // which `Database.execute` (and the underlying native `execSQL`)
      // rejects -- it must go through a query method instead.
      await db.rawQuery('SELECT InitSpatialMetaData(1)');
      await userOnConfigure?.call(db);
    },
    onCreate: options?.onCreate,
    onUpgrade: options?.onUpgrade,
    onDowngrade: options?.onDowngrade,
    onOpen: options?.onOpen,
    readOnly: options?.readOnly,
    singleInstance: options?.singleInstance,
  );
  return openDatabase(path, options: wrappedOptions);
}
