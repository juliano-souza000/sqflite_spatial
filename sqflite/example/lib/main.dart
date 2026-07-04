import 'package:flutter/material.dart';
import 'package:sqflite_example_common/main.dart';

import 'spatial_test_page.dart';

const _testSpatialRoute = '/test/spatial';

Future<void> main() async {
  supportsCompatMode = true;
  extraRoutes = {
    _testSpatialRoute: (BuildContext context) => SpatialTestPage(),
  };
  mainExampleApp();
}
