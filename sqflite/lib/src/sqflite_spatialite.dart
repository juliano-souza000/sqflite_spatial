import 'package:sqflite_common/sqlite_api.dart';

String _rtreeName(String table, String geomColumn) => 'idx_${table}_$geomColumn';

/// SpatiaLite spatial query helpers.
///
/// All methods build parameterized SQL calling SpatiaLite SQL functions and
/// run it through [DatabaseExecutor.rawQuery]/[DatabaseExecutor.execute] —
/// there is no additional native method channel surface. Geometries are
/// passed/returned as WKT (Well-Known Text, e.g. `'POINT(1 2)'`).
///
/// Queries that filter by geometry pre-filter using the R*Tree spatial index
/// (`idx_<table>_<geomColumn>`, created via `createSpatialIndexSql`) before
/// applying the exact SpatiaLite predicate — the standard SpatiaLite
/// performance idiom, since the R*Tree alone only tests bounding-box overlap.
///
/// Only produces correct results against a SpatiaLite-enabled native engine
/// (currently Android, opened via `openSpatialDatabase`).
extension SqfliteDatabaseSpatialiteExt on Database {
  /// The planar distance between the geometry in [geomColumn] of the row
  /// where [idColumn] equals [id], and the geometry described by [wkt], in
  /// the spatial reference system's units.
  ///
  /// Returns `null` if no row matches.
  Future<double?> spatialDistance(
    String table,
    String geomColumn,
    String wkt, {
    required String idColumn,
    required Object id,
  }) async {
    final rows = await rawQuery(
      'SELECT ST_Distance($geomColumn, GeomFromText(?)) AS distance '
      'FROM $table WHERE $idColumn = ?',
      [wkt, id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return (rows.first['distance'] as num?)?.toDouble();
  }

  /// The [limit] rows of [table] whose [geomColumn] is nearest to [wkt],
  /// ordered by ascending distance. Each returned row includes a `distance`
  /// column.
  ///
  /// Pre-filters using the R*Tree spatial index against [wkt]'s bounding box
  /// expanded by [searchBuffer] (in the spatial reference system's units) on
  /// every side, then ranks the candidates by exact `ST_Distance`. Rows
  /// outside the expanded search box are never considered — widen
  /// [searchBuffer] if fewer than [limit] rows come back.
  Future<List<Map<String, Object?>>> spatialNearest(
    String table,
    String geomColumn,
    String wkt, {
    int limit = 10,
    double searchBuffer = 1.0,
  }) => rawQuery(
    'SELECT t.*, ST_Distance(t.$geomColumn, GeomFromText(?)) AS distance '
    'FROM $table AS t, (SELECT ST_Expand(GeomFromText(?), ?) AS bbox) AS s '
    'WHERE t.ROWID IN ('
    '  SELECT ROWID FROM ${_rtreeName(table, geomColumn)}'
    '  WHERE xmin <= MbrMaxX(s.bbox) AND xmax >= MbrMinX(s.bbox)'
    '    AND ymin <= MbrMaxY(s.bbox) AND ymax >= MbrMinY(s.bbox)'
    ') '
    'ORDER BY distance LIMIT ?',
    [wkt, wkt, searchBuffer, limit],
  );

  /// The rows of [table] whose [geomColumn] is fully contained within the
  /// polygon described by [polygonWkt].
  Future<List<Map<String, Object?>>> spatialContains(
    String table,
    String geomColumn,
    String polygonWkt,
  ) => rawQuery(
    'SELECT t.* FROM $table AS t '
    'WHERE t.ROWID IN ('
    '  SELECT ROWID FROM ${_rtreeName(table, geomColumn)}'
    '  WHERE xmin <= MbrMaxX(GeomFromText(?)) AND xmax >= MbrMinX(GeomFromText(?))'
    '    AND ymin <= MbrMaxY(GeomFromText(?)) AND ymax >= MbrMinY(GeomFromText(?))'
    ') '
    'AND ST_Contains(GeomFromText(?), t.$geomColumn) = 1',
    [polygonWkt, polygonWkt, polygonWkt, polygonWkt, polygonWkt],
  );

  /// The rows of [table] whose [geomColumn] intersects the geometry
  /// described by [wkt].
  Future<List<Map<String, Object?>>> spatialIntersects(
    String table,
    String geomColumn,
    String wkt,
  ) => rawQuery(
    'SELECT t.* FROM $table AS t '
    'WHERE t.ROWID IN ('
    '  SELECT ROWID FROM ${_rtreeName(table, geomColumn)}'
    '  WHERE xmin <= MbrMaxX(GeomFromText(?)) AND xmax >= MbrMinX(GeomFromText(?))'
    '    AND ymin <= MbrMaxY(GeomFromText(?)) AND ymax >= MbrMinY(GeomFromText(?))'
    ') '
    'AND ST_Intersects(GeomFromText(?), t.$geomColumn) = 1',
    [wkt, wkt, wkt, wkt, wkt],
  );

  /// The rows of [table] whose [geomColumn]'s bounding box overlaps the
  /// rectangle `([minX], [minY])`-`([maxX], [maxY])`.
  ///
  /// A pure R*Tree query — the fastest and coarsest of the spatial filters,
  /// since it only tests bounding boxes, not exact geometry.
  Future<List<Map<String, Object?>>> spatialBoundingBoxFilter(
    String table,
    String geomColumn,
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) => rawQuery(
    'SELECT t.* FROM $table AS t '
    'WHERE t.ROWID IN ('
    '  SELECT ROWID FROM ${_rtreeName(table, geomColumn)}'
    '  WHERE xmin <= ? AND xmax >= ? AND ymin <= ? AND ymax >= ?'
    ')',
    [maxX, minX, maxY, minY],
  );
}
