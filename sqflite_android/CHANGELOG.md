## 3.0.0

* Breaking: replaces the native SQLite engine (`android.database.sqlite.SQLiteDatabase`) with
  a SpatiaLite-enabled fork (`org.spatialite.database.SQLiteDatabase` from
  `io.github.ev-map:android-spatialite`), enabling geospatial storage, indexing and querying
  (see `package:sqflite`'s `openSpatialDatabase` and `SqfliteDatabaseSpatialiteExt`). The
  MethodChannel wire protocol is unchanged, so existing non-spatial `sqflite` code keeps working
  as-is.
* Breaking: raises `minSdk` from 19 to 21, required by the vendored native library.
* Adds ~6MB per ABI to the built APK/AAB for the bundled native library (SQLite 3.49.1,
  SpatiaLite 4.3.0a, GEOS, Proj4, lwgeom; Apache 2.0). See README.md "Native binary provenance".
* Verified on a real Android 16 (API 36) emulator: all 8 spatial operations (metadata init,
  WKT insert/round-trip, distance, nearest, contains, intersects, bounding-box, v1->v2 migration)
  produce correct results end-to-end.
* Known regressions found via the same on-device run, not yet fixed (see README.md
  "Trade-offs to be aware of"):
  * `androidSetLocale`/`COLLATE LOCALIZED` no longer reorders rows by locale-aware collation.
  * `openReadOnlyDatabase` on a non-existent file path no longer throws — it now succeeds
    instead of failing as it does with the framework SQLite.
  * A failed open no longer surfaces the specific `ERROR_OPEN_FAILED` code (falls back to a
    generic `SQLITE_ERROR`), since `SQLiteCantOpenDatabaseException` is never thrown by this
    engine.

## 2.4.3

* Updates minimum supported SDK version to Flutter 3.44 / Dart 3.12.
* Migrates to built-in Kotlin.

## 2.4.2+3

* Use compile statement for insert/update and delete to avoid invalid result in wal mode
* Requires dart 3.10

## 2.4.2+2

* Requires compile SDK 36
* Requires dart 3.9

## 2.4.1

* Requires dart 3.7

## 2.4.0

* Initial implementation from sqflite v2.3.3+2
