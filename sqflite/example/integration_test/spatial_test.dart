import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide test;
import 'package:sqflite_spatial/sqflite.dart';
import 'package:test/test.dart' show test;

// ignore_for_file: avoid_print

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('spatialite', () {
    Future<Database> openPlaceDb(String path) => openSpatialDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) async {
          final batch = db.batch();
          batch.execute('DROP TABLE IF EXISTS Place');
          batch.execute('''CREATE TABLE Place (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT
          )''');
          batch.rawQuery(
            addGeometryColumnSql(
              'Place',
              'geom',
              srid: 4326,
              geometryType: 'POINT',
            ),
          );
          batch.rawQuery(createSpatialIndexSql('Place', 'geom'));
          await batch.commit();
        },
      ),
    );

    Future<void> insertSamplePlaces(Database db) async {
      const samples = <(String, String)>[
        ('Eiffel Tower', 'POINT(2.2945 48.8584)'),
        ('Louvre Museum', 'POINT(2.3364 48.8606)'),
        ('Notre-Dame', 'POINT(2.3499 48.8530)'),
        ('Arc de Triomphe', 'POINT(2.2950 48.8738)'),
      ];
      for (final (name, wkt) in samples) {
        await db.rawInsert(
          'INSERT INTO Place (name, geom) VALUES (?, GeomFromText(?, 4326))',
          [name, wkt],
        );
      }
    }

    test('InitSpatialMetaData + geometry_columns metadata', () async {
      const path = 'spatial_it_init.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        final metaData = await db.rawQuery(
          'SELECT f_table_name, f_geometry_column, srid, geometry_type '
          "FROM geometry_columns WHERE LOWER(f_table_name) = 'place'",
        );
        print('geometry_columns: $metaData');
        expect(metaData.length, 1);
        expect(metaData.first['f_geometry_column'], 'geom');
        expect(metaData.first['srid'], 4326);
      } finally {
        await db.close();
      }
    });

    test('insert + AsText round trip', () async {
      const path = 'spatial_it_roundtrip.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        await insertSamplePlaces(db);
        final rows = await db.rawQuery(
          'SELECT id, name, AsText(geom) AS wkt FROM Place ORDER BY id',
        );
        print('places: $rows');
        expect(rows.length, 4);
        expect(rows.first['name'], 'Eiffel Tower');
        expect(rows.first['wkt'], isA<String>());
        expect((rows.first['wkt'] as String).startsWith('POINT'), isTrue);
      } finally {
        await db.close();
      }
    });

    test('spatialDistance', () async {
      const path = 'spatial_it_distance.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        await insertSamplePlaces(db);
        final distance = await db.spatialDistance(
          'Place',
          'geom',
          'POINT(2.3364 48.8606)', // Louvre
          idColumn: 'name',
          id: 'Eiffel Tower',
        );
        print('distance Eiffel Tower -> Louvre: $distance');
        expect(distance, isNotNull);
        expect(distance! > 0, isTrue);
        // Same point -> zero distance.
        final zero = await db.spatialDistance(
          'Place',
          'geom',
          'POINT(2.2945 48.8584)',
          idColumn: 'name',
          id: 'Eiffel Tower',
        );
        expect(zero, closeTo(0, 0.0001));
      } finally {
        await db.close();
      }
    });

    test('spatialNearest', () async {
      const path = 'spatial_it_nearest.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        await insertSamplePlaces(db);
        final nearest = await db.spatialNearest(
          'Place',
          'geom',
          'POINT(2.2945 48.8584)', // exactly the Eiffel Tower
          limit: 2,
          searchBuffer: 0.2,
        );
        print('nearest: $nearest');
        expect(nearest.isNotEmpty, isTrue);
        // The Eiffel Tower itself must be the nearest (distance 0).
        expect(nearest.first['name'], 'Eiffel Tower');
        // Results must be sorted ascending by distance.
        for (var i = 1; i < nearest.length; i++) {
          expect(
            (nearest[i]['distance'] as num) >=
                (nearest[i - 1]['distance'] as num),
            isTrue,
          );
        }
      } finally {
        await db.close();
      }
    });

    test('spatialContains', () async {
      const path = 'spatial_it_contains.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        await insertSamplePlaces(db);
        // A small polygon around only the Eiffel Tower.
        const polygon =
            'POLYGON((2.29 48.855, 2.29 48.862, 2.30 48.862, 2.30 48.855, 2.29 48.855))';
        final inside = await db.spatialContains('Place', 'geom', polygon);
        print('contained in small polygon: $inside');
        expect(inside.length, 1);
        expect(inside.first['name'], 'Eiffel Tower');

        // A polygon covering all of central Paris should contain all 4.
        const bigPolygon =
            'POLYGON((2.28 48.85, 2.28 48.88, 2.36 48.88, 2.36 48.85, 2.28 48.85))';
        final allInside = await db.spatialContains(
          'Place',
          'geom',
          bigPolygon,
        );
        expect(allInside.length, 4);
      } finally {
        await db.close();
      }
    });

    test('spatialIntersects', () async {
      const path = 'spatial_it_intersects.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        await insertSamplePlaces(db);
        // A line passing very close to/through the Eiffel Tower point.
        const line = 'LINESTRING(2.2945 48.85, 2.2945 48.87)';
        final intersecting = await db.spatialIntersects('Place', 'geom', line);
        print('intersecting line: $intersecting');
        expect(
          intersecting.any((r) => r['name'] == 'Eiffel Tower'),
          isTrue,
        );
      } finally {
        await db.close();
      }
    });

    test('spatialBoundingBoxFilter', () async {
      const path = 'spatial_it_bbox.db';
      await deleteDatabase(path);
      final db = await openPlaceDb(path);
      try {
        await insertSamplePlaces(db);
        // Box covering only the Eiffel Tower and Arc de Triomphe (west side).
        final inBox = await db.spatialBoundingBoxFilter(
          'Place',
          'geom',
          2.29,
          48.85,
          2.30,
          48.88,
        );
        print('in bounding box: $inBox');
        final names = inBox.map((r) => r['name']).toSet();
        expect(names, {'Eiffel Tower', 'Arc de Triomphe'});
      } finally {
        await db.close();
      }
    });

    test('migration v1 -> v2 adds geometry column + index', () async {
      const path = 'spatial_it_migration.db';
      await deleteDatabase(path);
      var db = await openSpatialDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE Place (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT)',
            );
          },
        ),
      );
      await db.insert('Place', {'name': 'Pre-existing place'});
      await db.close();

      db = await openSpatialDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion == 1) {
              final batch = db.batch();
              batch.rawQuery(
                addGeometryColumnSql(
                  'Place',
                  'geom',
                  srid: 4326,
                  geometryType: 'POINT',
                ),
              );
              batch.rawQuery(createSpatialIndexSql('Place', 'geom'));
              await batch.commit();
            }
          },
        ),
      );
      try {
        final metaData = await db.rawQuery(
          "SELECT f_geometry_column FROM geometry_columns WHERE LOWER(f_table_name) = 'place'",
        );
        expect(metaData.length, 1);
        final rows = await db.query('Place');
        expect(rows.length, 1);
        expect(rows.first['name'], 'Pre-existing place');

        // The newly-added column/index must be immediately usable.
        await db.rawUpdate(
          'UPDATE Place SET geom = GeomFromText(?, 4326) WHERE name = ?',
          ['POINT(2.2945 48.8584)', 'Pre-existing place'],
        );
        final withGeom = await db.rawQuery(
          'SELECT AsText(geom) AS wkt FROM Place',
        );
        expect(
          (withGeom.first['wkt'] as String).startsWith('POINT'),
          isTrue,
        );
      } finally {
        await db.close();
      }
    });
  });
}
