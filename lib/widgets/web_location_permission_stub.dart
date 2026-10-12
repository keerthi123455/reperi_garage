import 'package:flutter/widgets.dart';

/// Android / iOS: never used (the apps use their normal permission flow).
/// Present only so the shared screens compile.
Future<bool> askForWebLocation(BuildContext context) async => true;

Future<void> showWebLocationBlockedHelp(BuildContext context) async {}
