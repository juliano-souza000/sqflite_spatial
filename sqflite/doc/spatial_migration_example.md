## Spatial migration example

This follows the same pattern as the [generic migration example](migration_example.md), applied to a
SpatiaLite-enabled database (Android only, see [version.md](version.md)): a table created plain at v1, then
given a geometry column and a spatial index at v2.

`openSpatialDatabase` must be used instead of `openDatabase`/`factory.openDatabase` so that
`SELECT InitSpatialMetaData(1)` runs before any `onCreate`/`onUpgrade` DDL — SpatiaLite's
`AddGeometryColumn`/`CreateSpatialIndex` functions depend on the `geometry_columns` metadata tables that
`InitSpatialMetaData` creates, so it must always run first.

```dart
// Our database path
String path;
// Our database once opened
Database db;
```

## 1st version

The first version creates a plain `Place` table, no geometry yet.

```dart
/// Create tables
void _createTablePlaceV1(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS Place');
  batch.execute('''CREATE TABLE Place (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT
)''');
}

// First version of the database
db = await openSpatialDatabase(path,
    options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          var batch = db.batch();
          _createTablePlaceV1(batch);
          await batch.commit();
        },
        onDowngrade: onDatabaseDowngradeDelete));

```

## 2nd version

Let's add a `geom` geometry column (a `POINT` in SRID 4326/WGS 84) to `Place`, plus a spatial index on it.

We handle the creation of a fresh database in `onCreate` (creating the table and the geometry column/index in
one go) and the schema migration of an existing v1 database in `onUpgrade` (adding the geometry column/index to
the already-existing table).

```dart
/// Create Place table V2 (table + geometry column + spatial index)
void _createTablePlaceV2(Batch batch) {
  batch.execute('DROP TABLE IF EXISTS Place');
  batch.execute('''CREATE TABLE Place (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT
)''');
  // AddGeometryColumn/CreateSpatialIndex are SQL functions invoked via
  // SELECT, so they must be run with rawQuery, not execute.
  batch.rawQuery(addGeometryColumnSql('Place', 'geom', srid: 4326, geometryType: 'POINT'));
  batch.rawQuery(createSpatialIndexSql('Place', 'geom'));
}

/// Update Place table V1 to V2 (add the geometry column + spatial index)
void _updateTablePlaceV1toV2(Batch batch) {
  batch.rawQuery(addGeometryColumnSql('Place', 'geom', srid: 4326, geometryType: 'POINT'));
  batch.rawQuery(createSpatialIndexSql('Place', 'geom'));
}

// 2nd version of the database
db = await openSpatialDatabase(path,
    options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          var batch = db.batch();
          _createTablePlaceV2(batch);
          await batch.commit();
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          var batch = db.batch();
          if (oldVersion == 1) {
            _updateTablePlaceV1toV2(batch);
          }
          await batch.commit();
        },
        onDowngrade: onDatabaseDowngradeDelete));

```

Once open, rows can be inserted with their geometry as WKT (Well-Known Text):

```dart
await db.rawInsert(
    'INSERT INTO Place (name, geom) VALUES (?, GeomFromText(?, 4326))',
    ['Home', 'POINT(2.3522 48.8566)']);
```

and queried with the spatial helpers in `SqfliteDatabaseSpatialiteExt` (`spatialDistance`, `spatialNearest`,
`spatialContains`, `spatialIntersects`, `spatialBoundingBoxFilter`) — see their doc comments for details.

As with any schema migration, you will have to restart your app when you change your application schema; Flutter
Hot-reload won't work unless you properly close currently opened databases.
