import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_spatial/sqlite_api.dart';
import 'package:sqflite_spatial/src/constant.dart';
import 'package:sqflite_spatial/src/mixin/factory.dart';

import 'src_mixin_test.dart';

void main() {
  group('mixin_factory', () {
    test('public', () {
      // ignore: unnecessary_statements
      buildDatabaseFactory;
      // ignore: unnecessary_statements
      SqfliteInvokeHandler;
    });
    test('buildDatabaseFactory', () async {
      final methods = <String>[];
      final factory = buildDatabaseFactory(
        invokeMethod: (String method, [Object? arguments]) async {
          methods.add(method);
          return mockResult(method);
        },
      );
      expect(factory is SqfliteInvokeHandler, isTrue);
      await factory.openDatabase(inMemoryDatabasePath);
      expect(methods, <String>['openDatabase']);
    });
  });
}
