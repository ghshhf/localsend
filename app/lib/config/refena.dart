import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/progress_provider.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:refena_inspector_client/refena_inspector_client.dart';

final _logger = Logger('Refena');

class CustomRefenaObserver extends RefenaMultiObserver {
  CustomRefenaObserver()
    : super(
        observers: [
          RefenaDebugObserver(
            onLine: (line) => _logger.info(line),
            exclude: _exclude,
          ),
          RefenaTracingObserver(
            limit: 100,
            exclude: _exclude,
          ),
          RefenaInspectorObserver(),
        ],
      );
}

bool _exclude(RefenaEvent event) {
  if (event is ChangeEvent) {
    return event.notifier is DiscoveryLogger ||
        event.notifier is LocalIpService ||
        event.notifier is ProgressNotifier;
  }
  if (event is ActionDispatchedEvent) {
    final actionType = event.action.runtimeType.toString();
    return actionType == '_FetchLocalIpAction';
  }
  if (event is ActionFinishedEvent) {
    final actionType = event.action.runtimeType.toString();
    return actionType == '_FetchLocalIpAction';
  }
  return false;
}
