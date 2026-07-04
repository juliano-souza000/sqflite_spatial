// All of these build `SELECT <function>(...)` SQL: SpatiaLite metadata
// functions are invoked as SQL scalar functions. Run the result through
// `rawQuery`/`Batch.rawQuery`, not `execute`/`Batch.execute` -- the latter
// (and the underlying native `execSQL`) rejects SELECT statements.

/// Builds the SQL for `AddGeometryColumn`, SpatiaLite's function for adding a
/// geometry column to an existing table and registering it in
/// `geometry_columns` metadata.
///
/// [srid] is the spatial reference system identifier (defaults to 4326,
/// WGS 84). [geometryType] is one of SpatiaLite's geometry type names
/// (`POINT`, `LINESTRING`, `POLYGON`, `MULTIPOINT`, `MULTILINESTRING`,
/// `MULTIPOLYGON`, `GEOMETRYCOLLECTION`). [dimension] is `2` for XY, `3` for
/// XYZ.
String addGeometryColumnSql(
  String table,
  String column, {
  int srid = 4326,
  String geometryType = 'POINT',
  int dimension = 2,
}) => "SELECT AddGeometryColumn('$table', '$column', $srid, '$geometryType', $dimension)";

/// Builds the SQL for `CreateSpatialIndex`, which creates the R*Tree spatial
/// index (`idx_<table>_<column>`) SpatiaLite uses to accelerate bounding-box
/// filtering for the given geometry column.
///
/// Must be called after [addGeometryColumnSql] has been executed for the
/// same [table]/[column].
String createSpatialIndexSql(String table, String column) =>
    "SELECT CreateSpatialIndex('$table', '$column')";

/// Builds the SQL for `RecoverSpatialIndex`, which rebuilds the R*Tree
/// spatial index for a geometry column.
///
/// Useful after bulk-importing geometries directly (bypassing triggers) or
/// after restoring from a backup.
String recoverSpatialIndexSql(String table, String column) =>
    "SELECT RecoverSpatialIndex('$table', '$column')";

/// Builds the SQL for `DiscardGeometryColumn`, which removes a geometry
/// column's `geometry_columns` metadata registration (and its spatial index,
/// if any) without dropping the underlying table column.
///
/// Useful in `onDowngrade`/`onUpgrade` migration paths that need to undo
/// [addGeometryColumnSql].
String discardGeometryColumnSql(String table, String column) =>
    "SELECT DiscardGeometryColumn('$table', '$column')";
