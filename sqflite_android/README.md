# sqflite_android

The Android implementation of the [sqflite](https://pub.dev/packages/sqflite) plugin.

## SpatiaLite support

Since 3.0.0, this plugin's native SQLite engine is `org.spatialite.database.SQLiteDatabase` (a
SpatiaLite-enabled, API-compatible fork of `android.database.sqlite.SQLiteDatabase`) instead of
the Android framework's built-in SQLite, so that `sqflite` can support spatial storage, indexing
and querying (`package:sqflite`'s `openSpatialDatabase` and `SqfliteDatabaseSpatialiteExt` — see
its `doc/spatial_migration_example.md`). The MethodChannel wire protocol is unchanged: existing
non-spatial code using `sqflite` continues to work without modification.

This is a native-engine swap affecting **every** consumer of this plugin, not just applications
using spatial features — see the trade-offs below.

### Native binary provenance

The vendored dependency is [`io.github.ev-map:android-spatialite`](https://central.sonatype.com/artifact/io.github.ev-map/android-spatialite)
(version `2.3.0-alpha`), published to Maven Central (immutable/signed), a fork of
[`dalgarins/android-spatialite`](https://github.com/dalgarins/android-spatialite) itself derived
from [`sevar83/android-spatialite`](https://github.com/sevar83/android-spatialite). It bundles:

* SQLite 3.49.1
* SpatiaLite 4.3.0a
* GEOS 3.4.2
* Proj4 4.8.0
* lwgeom 2.2.0

all under the Apache License 2.0 (the library itself is a direct fork of AOSP's own
`android.database.sqlite` sources, also Apache 2.0 — see its file headers).

Verify this is still the latest/appropriate version before relying on it in production; the
project moves quickly (multiple releases in late 2025) and a newer release may be available.

### Trade-offs to be aware of

* **minSdk raised from 19 to 21** — required by the vendored library. Any app whose users are on
  Android 19/20 devices will need to stay on `sqflite_android` 2.x.
* **APK/AAB size increase** — roughly 6MB per ABI for the bundled native library, applied to
  every app using this plugin, whether or not it uses spatial features.
* **Verified on a real Android 16 (API 36) emulator**: all 8 spatial operations work correctly
  end-to-end (metadata init, WKT insert/round-trip, distance, nearest, contains, intersects,
  bounding-box, v1->v2 migration), and 12 of 14 pre-existing non-spatial integration tests pass
  unchanged. Two confirmed regressions were found in that same run (not yet fixed):
  * **`androidSetLocale` / `COLLATE LOCALIZED` no longer reorders rows by locale** — this
    engine's connection doesn't wire up Android's ICU-based collation the way the framework
    SQLite does. Apps relying on locale-aware sort order are affected.
  * **`openReadOnlyDatabase` on a non-existent file no longer throws** — it now silently opens
    (and presumably creates) the file instead of failing, unlike the framework SQLite.
  * **Open-failure error code**: `org.spatialite.database`'s native open path does not throw the
    Android-specific `SQLiteCantOpenDatabaseException` subclass, so a failed open now surfaces as
    a generic `SQLITE_ERROR` rather than the more specific `ERROR_OPEN_FAILED` code
    `sqflite_android` previously reported for that case.
  * The full `sqflite_common_test` conformance suite (beyond the two integration test files
    exercised here) has not been run against a real device; treat that as the remaining gate
    before shipping to production.
