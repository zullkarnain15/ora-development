import 'package:web/web.dart' as web;

Future<bool> defaultReachabilityProbe() async => web.window.navigator.onLine;
