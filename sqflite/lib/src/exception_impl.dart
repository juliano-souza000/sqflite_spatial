import 'package:sqflite_spatial/src/services_impl.dart';
import 'package:sqflite_spatial/src/sqflite_import.dart';

/// Wrap any exception to a [DatabaseException]
Future<T> wrapDatabaseException<T>(Future<T> Function() action) async {
  try {
    final result = await action();
    return result;
  } on PlatformException catch (e) {
    if (e.code == sqliteErrorCode) {
      throw SqfliteDatabaseException(e.message!, e.details);
      //rethrow;
    } else {
      rethrow;
    }
  }
}
