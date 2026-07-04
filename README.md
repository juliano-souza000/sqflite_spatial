# sqflite_spatial

Android SQLite plugin for [Flutter](https://flutter.io) with **SpatiaLite** spatial query support:
geospatial storage, indexing (R\*Tree) and querying (distance, nearest-neighbor, polygon
containment, intersection, bounding-box filtering) on top of the familiar `sqflite` API.

* Support transactions and batches
* Automatic version management during open
* Helpers for insert/query/update/delete queries
* DB operations executed in a background thread
* Spatial helpers: `openSpatialDatabase`, `SqfliteDatabaseSpatialiteExt`
  (`spatialDistance`, `spatialNearest`, `spatialContains`, `spatialIntersects`,
  `spatialBoundingBoxFilter`), and DDL helpers (`addGeometryColumnSql`, `createSpatialIndexSql`,
  `recoverSpatialIndexSql`, `discardGeometryColumnSql`)

**Android only.** This is a fork of [tekartik/sqflite](https://github.com/tekartik/sqflite) —
all credit for the original `sqflite` plugin (the API design, the Dart/native plugin
architecture, and the vast majority of the code this fork builds on) goes to its author,
[Alex Tekartik](https://github.com/alextekartik). If you don't need spatial features, or you need
iOS/macOS/desktop/web support, use the original [`sqflite`](https://pub.dev/packages/sqflite)
package instead — it is more broadly supported and actively maintained upstream.

This fork replaces the Android platform implementation's native SQLite engine
(`android.database.sqlite.SQLiteDatabase`) with a SpatiaLite-enabled fork
(`org.spatialite.database.SQLiteDatabase`, via
[`io.github.ev-map/android-spatialite`](https://central.sonatype.com/artifact/io.github.ev-map/android-spatialite)),
so it only supports Android. The rest of the `sqflite` API surface (transactions, batches,
migrations, raw queries) is unchanged and works exactly as it does upstream.

## Getting started

Add both packages to your `pubspec.yaml` (not yet published to pub.dev — depend on them via git
or a local path until they are):

```yaml
dependencies:
  sqflite_spatial:
    git:
      url: https://github.com/<your-fork-url>/sqflite_spatial
      path: sqflite
  sqflite_spatial_android:
    git:
      url: https://github.com/<your-fork-url>/sqflite_spatial
      path: sqflite_android
```

## Usage

Import it exactly like `sqflite`:

```dart
import 'package:sqflite_spatial/sqflite.dart';
```

### Non-spatial usage

Everything from `sqflite` works unchanged:

```dart
var db = await openDatabase('my_db.db');
await db.execute('CREATE TABLE Test (id INTEGER PRIMARY KEY, value TEXT)');
await db.insert('Test', {'value': 'hello'});
var rows = await db.query('Test');
```

### Spatial usage

Use `openSpatialDatabase` instead of `openDatabase` so SpatiaLite's metadata tables are
initialized before your schema runs:

```dart
var db = await openSpatialDatabase(
  'my_spatial_db.db',
  options: OpenDatabaseOptions(
    version: 1,
    onCreate: (db, version) async {
      var batch = db.batch();
      batch.execute('CREATE TABLE Place (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)');
      // AddGeometryColumn/CreateSpatialIndex are SQL functions (SELECT ...), so they
      // must run via rawQuery, not execute.
      batch.rawQuery(addGeometryColumnSql('Place', 'geom', srid: 4326, geometryType: 'POINT'));
      batch.rawQuery(createSpatialIndexSql('Place', 'geom'));
      await batch.commit();
    },
  ),
);

// Insert a geometry from WKT (Well-Known Text).
await db.rawInsert(
  "INSERT INTO Place (name, geom) VALUES (?, GeomFromText(?, 4326))",
  ['Eiffel Tower', 'POINT(2.2945 48.8584)'],
);

// Nearest neighbors, distance, containment, intersection, bounding-box filter:
var nearest = await db.spatialNearest('Place', 'geom', 'POINT(2.30 48.86)', limit: 5);
var distance = await db.spatialDistance('Place', 'geom', 'POINT(2.3364 48.8606)',
    idColumn: 'name', id: 'Eiffel Tower');
var within = await db.spatialContains('Place', 'geom', 'POLYGON((...))');
var crossing = await db.spatialIntersects('Place', 'geom', 'LINESTRING(...)');
var inBox = await db.spatialBoundingBoxFilter('Place', 'geom', minX, minY, maxX, maxY);
```

See [`sqflite/doc/spatial_migration_example.md`](sqflite/doc/spatial_migration_example.md) for a
full example of adding a geometry column/index to an existing table via a schema migration, and
[`sqflite/example/lib/spatial_test_page.dart`](sqflite/example/lib/spatial_test_page.dart) for a
runnable demo covering all 5 spatial query types.

## Documentation

* [Package documentation](sqflite/README.md)
* [Native binary provenance / trade-offs](sqflite_android/README.md) — what's bundled, license,
  and known differences from the framework SQLite engine
* [Original `sqflite` documentation](https://github.com/tekartik/sqflite/blob/master/sqflite/README.md)
  for anything not specific to spatial support (the API is otherwise identical)
