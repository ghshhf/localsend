import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

const _methodChannel = MethodChannel('org.localsend.localsend_app/hotspot_relay');
final _logger = Logger('HotspotRelay');

/// Information about a hotspot or WiFi network.
class HotspotInfo {
  final String ssid;
  final String password;
  final bool isRunning;

  const HotspotInfo({
    required this.ssid,
    required this.password,
    required this.isRunning,
  });

  factory HotspotInfo.fromMap(Map<dynamic, dynamic> map) {
    return HotspotInfo(
      ssid: map['ssid'] as String? ?? '',
      password: map['password'] as String? ?? '',
      isRunning: map['isRunning'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'HotspotInfo(ssid: $ssid, isRunning: $isRunning)';
}

// ============================================================
//  HOST MODE API
// ============================================================

/// Start a local-only hotspot for peer relay.
///
/// Returns [HotspotInfo] with the SSID and password once the hotspot is running.
/// On Android 8.0+, uses [WifiManager.startLocalOnlyHotspot].
Future<HotspotInfo> startHotspot() async {
  _logger.info('Starting hotspot relay...');
  try {
    final result = await _methodChannel.invokeMethod<Map>('startHotspot');
    if (result == null) {
      throw Exception('Failed to start hotspot: null response');
    }
    return HotspotInfo.fromMap(result);
  } catch (e) {
    _logger.severe('Failed to start hotspot: $e');
    rethrow;
  }
}

/// Stop the current hotspot.
Future<void> stopHotspot() async {
  _logger.info('Stopping hotspot relay...');
  try {
    await _methodChannel.invokeMethod('stopHotspot');
  } catch (e) {
    _logger.severe('Failed to stop hotspot: $e');
  }
}

/// Check if the hotspot is currently active.
Future<bool> isHotspotActive() async {
  try {
    final result = await _methodChannel.invokeMethod<bool>('isHotspotActive');
    return result ?? false;
  } catch (e) {
    _logger.warning('Failed to check hotspot status: $e');
    return false;
  }
}

/// Get current hotspot info.
Future<HotspotInfo> getHotspotInfo() async {
  try {
    final result = await _methodChannel.invokeMethod<Map>('getHotspotInfo');
    if (result == null) {
      return const HotspotInfo(ssid: '', password: '', isRunning: false);
    }
    return HotspotInfo.fromMap(result);
  } catch (e) {
    _logger.warning('Failed to get hotspot info: $e');
    return const HotspotInfo(ssid: '', password: '', isRunning: false);
  }
}

// ============================================================
//  CLIENT MODE API
// ============================================================

/// Connect to a peer's hotspot WiFi network.
///
/// On Android 10+, uses [WifiNetworkSpecifier] for seamless connection.
/// On older devices, uses [WifiManager] configuration.
Future<bool> connectToHotspot({
  required String ssid,
  required String password,
}) async {
  _logger.info('Connecting to hotspot: $ssid');
  try {
    final result = await _methodChannel.invokeMethod<Map>('connectToWifi', {
      'ssid': ssid,
      'password': password,
    });
    return result?['connected'] == true;
  } catch (e) {
    _logger.severe('Failed to connect to hotspot: $e');
    return false;
  }
}

/// Disconnect from the current hotspot network.
Future<void> disconnectHotspot() async {
  _logger.info('Disconnecting from hotspot...');
  try {
    await _methodChannel.invokeMethod('disconnectWifi');
  } catch (e) {
    _logger.warning('Failed to disconnect: $e');
  }
}

/// Check if currently connected to a hotspot (no-internet WiFi).
Future<bool> isConnectedToHotspot() async {
  try {
    final result = await _methodChannel.invokeMethod<bool>('isConnectedToHotspot');
    return result ?? false;
  } catch (e) {
    return false;
  }
}
