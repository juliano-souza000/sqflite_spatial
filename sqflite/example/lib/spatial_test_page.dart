import 'package:sqflite_example_common/test_page.dart';
import 'package:sqflite_spatial/sqflite.dart';

// ignore_for_file: avoid_print

/// Demonstrates SpatiaLite spatial storage/indexing/querying (Android only).
class SpatialTestPage extends TestPage {
  /// Spatial test page.
  SpatialTestPage({super.key}) : super('Spatial tests') {
    Future<Database> openPlaceDbV1(String path) => openSpatialDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          final batch = db.batch();
          batch.execute('DROP TABLE IF EXISTS Place');
          batch.execute('''CREATE TABLE Place (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT
          )''');
          await batch.commit();
        },
        onDowngrade: onDatabaseDowngradeDelete,
      ),
    );

    Future<Database> openPlaceDbV2(String path) => openSpatialDatabase(
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
        onUpgrade: (db, oldVersion, newVersion) async {
          final batch = db.batch();
          if (oldVersion == 1) {
            batch.rawQuery(
              addGeometryColumnSql(
                'Place',
                'geom',
                srid: 4326,
                geometryType: 'POINT',
              ),
            );
            batch.rawQuery(createSpatialIndexSql('Place', 'geom'));
          }
          await batch.commit();
        },
        onDowngrade: onDatabaseDowngradeDelete,
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

    test('Init and create spatial table + index', () async {
      final path = await initDeleteDb('spatial_init.db');
      final db = await openPlaceDbV2(path);
      try {
        final metaData = await db.rawQuery(
          'SELECT f_table_name, f_geometry_column, srid, geometry_type '
          "FROM geometry_columns WHERE LOWER(f_table_name) = 'place'",
        );
        print('geometry_columns: $metaData');
        expect(metaData.length, 1);
        expect(metaData.first['f_geometry_column'], 'geom');
      } finally {
        await db.close();
      }
    });

    test('Insert and retrieve geometry data', () async {
      final path = await initDeleteDb('spatial_insert.db');
      final db = await openPlaceDbV2(path);
      try {
        await insertSamplePlaces(db);
        final rows = await db.rawQuery(
          'SELECT id, name, AsText(geom) AS wkt FROM Place ORDER BY id',
        );
        print('places: $rows');
        expect(rows.length, 4);
        expect(rows.first['name'], 'Eiffel Tower');
      } finally {
        await db.close();
      }
    });

    test('Distance query', () async {
      final path = await initDeleteDb('spatial_distance.db');
      final db = await openPlaceDbV2(path);
      try {
        await insertSamplePlaces(db);
        // Distance from the Eiffel Tower's row to the Louvre.
        final distance = await db.spatialDistance(
          'Place',
          'geom',
          'POINT(2.3364 48.8606)',
          idColumn: 'name',
          id: 'Eiffel Tower',
        );
        print('distance Eiffel Tower -> Louvre: $distance');
        expect(distance != null && distance > 0, isTrue);
      } finally {
        await db.close();
      }
    });

    test('Nearest (proximity) query', () async {
      final path = await initDeleteDb('spatial_nearest.db');
      final db = await openPlaceDbV2(path);
      try {
        await insertSamplePlaces(db);
        final nearest = await db.spatialNearest(
          'Place',
          'geom',
          'POINT(2.30 48.86)',
          limit: 2,
          searchBuffer: 0.1,
        );
        print('nearest: $nearest');
        expect(nearest.isNotEmpty, isTrue);
      } finally {
        await db.close();
      }
    });

    test('Polygon containment query', () async {
      final path = await initDeleteDb('spatial_contains.db');
      final db = await openPlaceDbV2(path);
      try {
        await insertSamplePlaces(db);
        // A polygon roughly covering central Paris.
        const polygon =
            'POLYGON((2.28 48.85, 2.28 48.87, 2.36 48.87, 2.36 48.85, 2.28 48.85))';
        final inside = await db.spatialContains('Place', 'geom', polygon);
        print('contained in polygon: $inside');
        expect(inside.isNotEmpty, isTrue);
      } finally {
        await db.close();
      }
    });

    test('Intersection query', () async {
      final path = await initDeleteDb('spatial_intersects.db');
      final db = await openPlaceDbV2(path);
      try {
        await insertSamplePlaces(db);
        const line = 'LINESTRING(2.29 48.85, 2.35 48.87)';
        final intersecting = await db.spatialIntersects('Place', 'geom', line);
        print('intersecting line: $intersecting');
      } finally {
        await db.close();
      }
    });

    test('Bounding-box filter query', () async {
      final path = await initDeleteDb('spatial_bbox.db');
      final db = await openPlaceDbV2(path);
      try {
        await insertSamplePlaces(db);
        final inBox = await db.spatialBoundingBoxFilter(
          'Place',
          'geom',
          2.29,
          48.85,
          2.34,
          48.87,
        );
        print('in bounding box: $inBox');
        expect(inBox.isNotEmpty, isTrue);
      } finally {
        await db.close();
      }
    });

    test('Migration: add geometry column + index (v1 -> v2)', () async {
      final path = await initDeleteDb('spatial_migration.db');
      var db = await openPlaceDbV1(path);
      await db.insert('Place', {'name': 'Pre-existing place'});
      await db.close();

      // Reopen at version 2: onUpgrade adds the geometry column + index.
      db = await openPlaceDbV2(path);
      try {
        final metaData = await db.rawQuery(
          "SELECT f_geometry_column FROM geometry_columns WHERE LOWER(f_table_name) = 'place'",
        );
        expect(metaData.length, 1);
        final rows = await db.query('Place');
        expect(rows.length, 1);
        expect(rows.first['name'], 'Pre-existing place');
      } finally {
        await db.close();
      }
    });
  }
}
