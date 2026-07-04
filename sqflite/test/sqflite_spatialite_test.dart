import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_spatial/sqflite.dart';

T? _ambiguate<T>(T? value) => value;

const channel = MethodChannel('com.tekartik.sqflite');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactorySqflitePlugin;

  group('spatialite ddl', () {
    test('addGeometryColumnSql defaults', () {
      expect(
        addGeometryColumnSql('Place', 'geom'),
        "SELECT AddGeometryColumn('Place', 'geom', 4326, 'POINT', 2)",
      );
    });

    test('addGeometryColumnSql custom', () {
      expect(
        addGeometryColumnSql(
          'Place',
          'geom',
          srid: 3857,
          geometryType: 'POLYGON',
          dimension: 3,
        ),
        "SELECT AddGeometryColumn('Place', 'geom', 3857, 'POLYGON', 3)",
      );
    });

    test('createSpatialIndexSql', () {
      expect(
        createSpatialIndexSql('Place', 'geom'),
        "SELECT CreateSpatialIndex('Place', 'geom')",
      );
    });

    test('recoverSpatialIndexSql', () {
      expect(
        recoverSpatialIndexSql('Place', 'geom'),
        "SELECT RecoverSpatialIndex('Place', 'geom')",
      );
    });

    test('discardGeometryColumnSql', () {
      expect(
        discardGeometryColumnSql('Place', 'geom'),
        "SELECT DiscardGeometryColumn('Place', 'geom')",
      );
    });
  });

  group('spatialite queries', () {
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      _ambiguate(TestDefaultBinaryMessengerBinding.instance)!
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
            log.add(methodCall);
            switch (methodCall.method) {
              case 'openDatabase':
                return 1;
              case 'closeDatabase':
                return null;
              case 'execute':
                return null;
              case 'query':
                return <String, Object?>{
                  'columns': <String>[],
                  'rows': <List<Object?>>[],
                };
            }
            return null;
          });
    });

    Future<Map<String, Object?>> lastQueryArguments(
      Future<void> Function() action,
    ) async {
      await action();
      final call = log.lastWhere((call) => call.method == 'query');
      return (call.arguments as Map).cast<String, Object?>();
    }

    test('spatialDistance', () async {
      final db = await openSpatialDatabase(inMemoryDatabasePath);
      final args = await lastQueryArguments(
        () => db.spatialDistance(
          'Place',
          'geom',
          'POINT(1 2)',
          idColumn: 'id',
          id: 5,
        ),
      );
      expect(
        args['sql'],
        'SELECT ST_Distance(geom, GeomFromText(?)) AS distance '
        'FROM Place WHERE id = ?',
      );
      expect(args['arguments'], ['POINT(1 2)', 5]);
      await db.close();
    });

    test('spatialNearest', () async {
      final db = await openSpatialDatabase(inMemoryDatabasePath);
      final args = await lastQueryArguments(
        () => db.spatialNearest('Place', 'geom', 'POINT(1 2)', limit: 3),
      );
      expect(
        args['sql'],
        'SELECT t.*, ST_Distance(t.geom, GeomFromText(?)) AS distance '
        'FROM Place AS t, (SELECT ST_Expand(GeomFromText(?), ?) AS bbox) AS s '
        'WHERE t.ROWID IN ('
        '  SELECT ROWID FROM idx_Place_geom'
        '  WHERE xmin <= MbrMaxX(s.bbox) AND xmax >= MbrMinX(s.bbox)'
        '    AND ymin <= MbrMaxY(s.bbox) AND ymax >= MbrMinY(s.bbox)'
        ') '
        'ORDER BY distance LIMIT ?',
      );
      expect(args['arguments'], ['POINT(1 2)', 'POINT(1 2)', 1.0, 3]);
      await db.close();
    });

    test('spatialContains', () async {
      final db = await openSpatialDatabase(inMemoryDatabasePath);
      const polygon = 'POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))';
      final args = await lastQueryArguments(
        () => db.spatialContains('Place', 'geom', polygon),
      );
      expect(
        args['sql'],
        'SELECT t.* FROM Place AS t '
        'WHERE t.ROWID IN ('
        '  SELECT ROWID FROM idx_Place_geom'
        '  WHERE xmin <= MbrMaxX(GeomFromText(?)) AND xmax >= MbrMinX(GeomFromText(?))'
        '    AND ymin <= MbrMaxY(GeomFromText(?)) AND ymax >= MbrMinY(GeomFromText(?))'
        ') '
        'AND ST_Contains(GeomFromText(?), t.geom) = 1',
      );
      expect(args['arguments'], [polygon, polygon, polygon, polygon, polygon]);
      await db.close();
    });

    test('spatialIntersects', () async {
      final db = await openSpatialDatabase(inMemoryDatabasePath);
      final args = await lastQueryArguments(
        () => db.spatialIntersects('Place', 'geom', 'POINT(1 2)'),
      );
      expect(
        args['sql'],
        'SELECT t.* FROM Place AS t '
        'WHERE t.ROWID IN ('
        '  SELECT ROWID FROM idx_Place_geom'
        '  WHERE xmin <= MbrMaxX(GeomFromText(?)) AND xmax >= MbrMinX(GeomFromText(?))'
        '    AND ymin <= MbrMaxY(GeomFromText(?)) AND ymax >= MbrMinY(GeomFromText(?))'
        ') '
        'AND ST_Intersects(GeomFromText(?), t.geom) = 1',
      );
      expect(args['arguments'], [
        'POINT(1 2)',
        'POINT(1 2)',
        'POINT(1 2)',
        'POINT(1 2)',
        'POINT(1 2)',
      ]);
      await db.close();
    });

    test('spatialBoundingBoxFilter', () async {
      final db = await openSpatialDatabase(inMemoryDatabasePath);
      final args = await lastQueryArguments(
        () => db.spatialBoundingBoxFilter('Place', 'geom', 0, 1, 10, 11),
      );
      expect(
        args['sql'],
        'SELECT t.* FROM Place AS t '
        'WHERE t.ROWID IN ('
        '  SELECT ROWID FROM idx_Place_geom'
        '  WHERE xmin <= ? AND xmax >= ? AND ymin <= ? AND ymax >= ?'
        ')',
      );
      expect(args['arguments'], [10.0, 0.0, 11.0, 1.0]);
      await db.close();
    });

    test('openSpatialDatabase runs InitSpatialMetaData before onConfigure', () async {
      final order = <String>[];
      final db = await openSpatialDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          onConfigure: (db) async {
            order.add('user onConfigure');
          },
        ),
      );
      final queryCalls = log.where((call) => call.method == 'query').toList();
      expect(
        (queryCalls.first.arguments as Map)['sql'],
        'SELECT InitSpatialMetaData(1)',
      );
      expect(order, ['user onConfigure']);
      await db.close();
    });
  });
}
