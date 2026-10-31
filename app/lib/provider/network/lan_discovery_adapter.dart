import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:localsend_app/util/transport/local_network_transport.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Adapts the app-wide device discovery to the narrow [LanDiscovery] view the
/// PRP LAN transport needs.
///
/// The discovery itself runs in the discovery isolate and is owned by
/// [nearbyDevicesProvider]; this adapter only reads its device store and
/// triggers its scan actions. It never starts or stops the discovery: that
/// would blank the send tab every time a PRP connection closes.
class NearbyDevicesLanDiscovery implements LanDiscovery {
  NearbyDevicesLanDiscovery(this._ref);

  final Ref _ref;

  @override
  Map<String, Device> get snapshot => _ref.read(nearbyDevicesProvider).devices;

  @override
  Stream<Map<String, Device>> get changes => _ref.stream(nearbyDevicesProvider).map((event) => event.next.devices);

  @override
  void announce() {
    _ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());
  }

  @override
  Future<void> probe() => _ref.global.dispatchAsync(StartSmartScan());
}
