import 'dart:io';

import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

final _logger = Logger('WifiHotspotPermissions');

/// Makes sure the runtime permissions required for hotspot relay are granted.
///
/// Android splits the requirement across versions:
/// - API 33+ (`TIRAMISU`): `NEARBY_WIFI_DEVICES`, a dangerous permission that
///   has to be requested at runtime. `ACCESS_FINE_LOCATION` is no longer needed.
/// - API 26-32: `ACCESS_FINE_LOCATION`, plus location services must be enabled
///   system-wide, otherwise `startLocalOnlyHotspot` fails with a generic error.
///
/// Returns `null` when the device may proceed, or a user-facing reason when it
/// may not. Callers surface the reason through their regular error state instead
/// of starting an operation that the platform will reject.
Future<String?> ensureHotspotPermissions() async {
  if (!Platform.isAndroid) {
    return null;
  }

  // Android 13+ path. On older releases this permission is unknown to the
  // platform, so a denial here is expected and the location path below covers it.
  final nearby = await Permission.nearbyWifiDevices.request();
  if (nearby.isGranted) {
    return null;
  }
  if (nearby.isPermanentlyDenied) {
    return 'Nearby devices permission is blocked. Allow it in system settings to use hotspot relay.';
  }

  // Android 8-12 path.
  final locationService = await Permission.location.serviceStatus;
  if (!locationService.isEnabled) {
    return 'Turn on system location. Android 8-12 requires it to create a hotspot.';
  }

  final location = await Permission.locationWhenInUse.request();
  if (location.isGranted) {
    return null;
  }
  if (location.isPermanentlyDenied) {
    return 'Location permission is blocked. Allow it in system settings to use hotspot relay.';
  }

  _logger.warning('Hotspot permissions denied (nearby: $nearby, location: $location)');
  return 'Hotspot relay needs the nearby devices or location permission.';
}
