import 'package:unittest/unittest.dart';

import 'net_test.dart' as net_test;
import '../../../dart2dserver/bin/test/http_test.dart' as http_test;

void main() {
  net_test.main();
  http_test.main();
}