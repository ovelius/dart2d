import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';


import 'test_injector.config.dart';
final getIt = GetIt.instance;

@InjectableInit(
  generateForDir: ['test/lib', 'lib'],
  initializerName: 'init', // default
  preferRelativeImports: true, // default
  asExtension: true, // default
)
void configureDependencies() => getIt.init();