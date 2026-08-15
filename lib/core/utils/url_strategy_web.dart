// lib/core/utils/url_strategy_web.dart
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void configureUrlStrategy() {
  setUrlStrategy(PathUrlStrategy());
}