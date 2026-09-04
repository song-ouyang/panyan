import 'package:flutter/material.dart';

import 'app/wanpan_bootstrap.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WanpanBootstrap(config: AppConfig.fromEnvironment()));
}
