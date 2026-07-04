import 'package:flutter/cupertino.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_spatial/src/factory.dart';
import 'package:sqflite_spatial/src/factory_impl.dart';

export 'package:sqflite_spatial/src/factory_impl.dart'
    show sqfliteDatabaseFactoryDefault;

/// Change the default factory used.
///
/// Test only.
///
@visibleForTesting
void setMockDatabaseFactory(DatabaseFactory? factory) {
  // ignore: invalid_use_of_visible_for_testing_member
  sqfliteDatabaseFactory = factory as SqfliteDatabaseFactory?;
}
