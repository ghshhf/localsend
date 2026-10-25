import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/util/transport/transports.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('PrpService');

/// PRP (Peer Relay Protocol) modes
enum PrpMode {
  /// Device creates a hotspot and waits for peers
  host,

  /// Device scans/connects to a peer's hotspot
  client,

  /// No PRP activity
  idle,
}

/// PRP connection state
enum PrpConnectionState {
  /// Initial state
  idle,

  /// Starting hotspot / connecting to hotspot
  connecting,

  /// Hotspot is running / connected to peer hotspot
  connected,

  /// Error occurred
  error,

  /// Disconnected
  disconnected,
}

/// PRP state container.
class PrpState {
  final PrpMode mode;
  final PrpConnectionState state;
  final TransportType transportType;
  final String? networkName;
  final String? networkPassword;
  final String? ipAddress;
  final String? errorMessage;
  final bool isUsbTetheringAvailable;

  /// Transport types usable on this device, populated async during init.
  /// Kept in state so the UI can watch it reactively.
  final List<TransportType> availableTransports;

  /// Relay bridge: public node URL this device is linked to (PRP 远程中继桥).
  final String? relayUrl;

  /// Relay-assigned device id (from /api/prp/register).
  final String? relayDeviceId;

  /// Last instruction received from the relay.
  final String? relayInstruction;

  /// Last echo / relay-sent message received back.
  final String? relayLastEcho;

  const PrpState({
    this.mode = PrpMode.idle,
    this.state = PrpConnectionState.idle,
    this.transportType = TransportType.wifiHotspot,
    this.networkName,
    this.networkPassword,
    this.ipAddress,
    this.errorMessage,
    this.isUsbTetheringAvailable = false,
    this.availableTransports = const [],
    this.relayUrl,
    this.relayDeviceId,
    this.relayInstruction,
    this.relayLastEcho,
  });

  bool get isActive => mode != PrpMode.idle;

  PrpState copyWith({
    PrpMode? mode,
    PrpConnectionState? state,
    TransportType? transportType,
    String? networkName,
    String? networkPassword,
    String? ipAddress,
    String? errorMessage,
    bool clearError = false,
    bool? isUsbTetheringAvailable,
    List<TransportType>? availableTransports,
    String? relayUrl,
    String? relayDeviceId,
    String? relayInstruction,
    String? relayLastEcho,
    bool clearRelay = false,
    bool clearNetwork = false,
  }) {
    // 传 null 在 copyWith 里等于「不改」，所以想清空必须显式 clearNetwork: true
    // （同 clearError / clearRelay 的写法）。三个连接期字段一起受它控制。
    return PrpState(
      mode: mode ?? this.mode,
      state: state ?? this.state,
      transportType: transportType ?? this.transportType,
      networkName: clearNetwork ? null : (networkName ?? this.networkName),
      networkPassword: clearNetwork ? null : (networkPassword ?? this.networkPassword),
      ipAddress: clearNetwork ? null : (ipAddress ?? this.ipAddress),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isUsbTetheringAvailable: isUsbTetheringAvailable ?? this.isUsbTetheringAvailable,
      availableTransports: availableTransports ?? this.availableTransports,
      // relay 四个字段共用 clearRelay 开关：传 null 表示"不改"，
      // 要清空必须显式 clearRelay: true（同 errorMessage/clearError 的写法）。
      relayUrl: clearRelay ? null : (relayUrl ?? this.relayUrl),
      relayDeviceId: clearRelay ? null : (relayDeviceId ?? this.relayDeviceId),
      relayInstruction: clearRelay ? null : (relayInstruction ?? this.relayInstruction),
      relayLastEcho: clearRelay ? null : (relayLastEcho ?? this.relayLastEcho),
    );
  }
}

final prpProvider = ReduxProvider<PrpService, PrpState>((ref) {
  return PrpService();
});

/// PRP (Peer Relay Protocol) service.
///
/// Manages the lifecycle of peer relay connections using a unified
/// transport abstraction. Supports multiple transport types:
/// - WiFi hotspot relay (cross-platform)
/// - USB tethering (Android 5.0+)
class PrpService extends ReduxNotifier<PrpState> {
  final TransportManager _transportManager = TransportManager();

  @override
  PrpState init() {
    // Async initialization: push transport availability into state once the
    // transport manager is ready. Fire-and-forget is required because
    // ReduxNotifier.init() must return synchronously; by the time the future
    // completes the provider is mounted, so writing state here is safe.
    _transportManager
        .init()
        .then((_) {
          final available = _transportManager.availableTransports;
          // ignore: invalid_use_of_internal_member — async init result must
          // reach the state; this is the notifier itself, not an action.
          state = state.copyWith(
            isUsbTetheringAvailable: available.contains(
              TransportType.usbTethering,
            ),
            availableTransports: available,
          );
        })
        .catchError((Object e, StackTrace st) {
          _logger.warning('TransportManager init failed: $e', e, st);
        });
    return const PrpState();
  }

  /// Get available transport types for UI display.
  List<TransportType> get availableTransports => _transportManager.availableTransports;

  /// Access the transport manager (for direct transport operations).
  TransportManager get transportManager => _transportManager;

  @override
  void dispose() {
    // BaseNotifier.dispose() is synchronous, while teardown closes stream
    // controllers — fire-and-forget is the only option. The error is swallowed
    // explicitly so a teardown failure cannot surface as an unhandled async
    // error in the zone (which would fail binding-less unit tests).
    unawaited(
      _transportManager.dispose().catchError((Object e, StackTrace st) {
        _logger.warning('TransportManager dispose failed: $e', e, st);
      }),
    );
    super.dispose();
  }
}

/// Start PRP in host mode using the specified transport.
class StartHostAction extends AsyncReduxAction<PrpService, PrpState> {
  final TransportType transportType;
  final String alias;

  StartHostAction({
    this.transportType = TransportType.wifiHotspot,
    this.alias = 'LocalSend',
  });

  @override
  Future<PrpState> reduce() async {
    _logger.info('Starting PRP host mode via $transportType');

    // Update state to "connecting" for immediate UI feedback.
    // ignore: internal_member — notifier.state is the intended way to
    // push interim state updates within AsyncReduxAction in Refena.
    //noinspection: invalid_use_of_internal_member
    notifier.state = state.copyWith(
      mode: PrpMode.host,
      state: PrpConnectionState.connecting,
      transportType: transportType,
      clearError: true,
    );

    final success = await notifier._transportManager.startHost(
      type: transportType,
      config: HostConfig(alias: alias),
    );

    if (success) {
      final info = notifier._transportManager.activeInfo;
      return state.copyWith(
        state: PrpConnectionState.connected,
        networkName: info?.networkName,
        networkPassword: info?.password,
        ipAddress: info?.metadata['ipAddress'] as String?,
      );
    } else {
      // Failure resets mode to idle: host mode is not active if startup failed.
      return state.copyWith(
        mode: PrpMode.idle,
        state: PrpConnectionState.error,
        errorMessage: notifier._transportManager.activeError ?? 'Failed to start host mode',
      );
    }
  }
}

/// Stop PRP host mode.
class StopHostAction extends AsyncReduxAction<PrpService, PrpState> {
  @override
  Future<PrpState> reduce() async {
    _logger.info('Stopping PRP host mode');
    final stopped = await notifier._transportManager.stopActive();
    return state.copyWith(
      mode: PrpMode.idle,
      state: stopped ? PrpConnectionState.disconnected : PrpConnectionState.error,
      // 三处 null 改由 clearNetwork 驱动：直接传 null 是「不改」，清不掉。
      clearNetwork: true,
      errorMessage: stopped ? null : 'Failed to stop host mode',
      clearError: stopped,
    );
  }
}

/// Connect to a peer as client.
class ConnectToPeerAction extends AsyncReduxAction<PrpService, PrpState> {
  final TransportType transportType;
  final String ssid;
  final String password;

  ConnectToPeerAction({
    this.transportType = TransportType.wifiHotspot,
    required this.ssid,
    required this.password,
  });

  @override
  Future<PrpState> reduce() async {
    _logger.info('Connecting to peer via $transportType: $ssid');

    // ignore: internal_member — interim state push for UI feedback
    //noinspection: invalid_use_of_internal_member
    notifier.state = state.copyWith(
      mode: PrpMode.client,
      state: PrpConnectionState.connecting,
      transportType: transportType,
      clearError: true,
    );

    final success = await notifier._transportManager.connectToHost(
      type: transportType,
      config: ConnectConfig(ssid: ssid, password: password),
    );

    if (success) {
      final info = notifier._transportManager.activeInfo;
      return state.copyWith(
        state: PrpConnectionState.connected,
        networkName: info?.networkName ?? ssid,
        networkPassword: info?.password ?? password,
        ipAddress: info?.metadata['ipAddress'] as String?,
      );
    } else {
      // Failure resets mode to idle: client mode is not active if connect failed.
      return state.copyWith(
        mode: PrpMode.idle,
        state: PrpConnectionState.error,
        errorMessage: notifier._transportManager.activeError ?? 'Failed to connect',
      );
    }
  }
}

/// Disconnect from peer.
class DisconnectPeerAction extends AsyncReduxAction<PrpService, PrpState> {
  @override
  Future<PrpState> reduce() async {
    _logger.info('Disconnecting from peer');
    await notifier._transportManager.disconnectActive();
    return state.copyWith(
      mode: PrpMode.idle,
      state: PrpConnectionState.disconnected,
      clearNetwork: true,
      clearError: true,
    );
  }
}

/// Switch transport type.
class SwitchTransportAction extends ReduxAction<PrpService, PrpState> {
  final TransportType transportType;

  SwitchTransportAction(this.transportType);

  @override
  PrpState reduce() {
    _logger.info('Switching transport to $transportType');
    return state.copyWith(transportType: transportType);
  }
}

/// Refresh transport status.
class RefreshPrpStatusAction extends AsyncReduxAction<PrpService, PrpState> {
  @override
  Future<PrpState> reduce() async {
    final transport = notifier._transportManager.activeTransport;
    if (transport == null) return state;

    if (transport is WifiHotspotTransport) {
      final info = await transport.getCurrentInfo();
      return state.copyWith(
        networkName: info.networkName,
        networkPassword: info.password,
      );
    }

    return state;
  }
}

/// Reset PRP state.
class ResetPrpAction extends AsyncReduxAction<PrpService, PrpState> {
  @override
  Future<PrpState> reduce() async {
    await notifier._transportManager.disconnectActive();
    // Preserve device-level transport availability: it reflects the platform,
    // not the connection lifecycle.
    return const PrpState().copyWith(
      isUsbTetheringAvailable: state.isUsbTetheringAvailable,
      availableTransports: state.availableTransports,
    );
  }
}

/// Connect PRP to a remote public relay node and run a self-check handshake.
///
/// Small bridge: register (self-check) → receive instruction → send content back
/// → receive echo. Lets a phone-side PRP talk to the public 7x24 relay.
class ConnectToRelayAction extends AsyncReduxAction<PrpService, PrpState> {
  final String relayUrl;
  final String alias;

  ConnectToRelayAction({required this.relayUrl, this.alias = 'LocalSend'});

  @override
  Future<PrpState> reduce() async {
    _logger.info('Connecting PRP to relay: $relayUrl');

    // 1) 自检：把当前 PRP 状态打包成 self-check 负载
    final selfCheck = <String, dynamic>{
      'mode': state.mode.name,
      'connection': state.state.name,
      'transport': state.transportType.name,
      'available': state.availableTransports.map((t) => t.name).toList(),
      'has_active': notifier.transportManager.activeTransport != null,
    };

    // 2) 注册 + 收指令
    final reg = await _relayPost(
      '$relayUrl/api/prp/register',
      {'alias': alias, 'self_check': selfCheck},
    );
    if (reg == null || reg['ok'] != true) {
      return state.copyWith(
        relayUrl: relayUrl,
        state: PrpConnectionState.error,
        errorMessage: '中继注册失败（检查公网地址是否可达）',
      );
    }
    final deviceId = (reg['device_id'] as String?) ?? '';
    if (deviceId.isEmpty) {
      // device_id 是中继侧唯一的会话句柄；空着继续走，后续 message 全都无法归类。
      return state.copyWith(
        relayUrl: relayUrl,
        state: PrpConnectionState.error,
        errorMessage: '中继注册未返回 device_id',
      );
    }
    final instruction = (reg['instruction'] as String?) ?? '';

    // 3) 收到指令后，把自检内容发回中继，并取回 echo（含 relay 侧排队消息）
    final msg = await _relayPost(
      '$relayUrl/api/prp/message',
      {'device_id': deviceId, 'content': selfCheck},
    );
    // 注册成功但回传失败 = 握手没闭环。早前这里会用 null echo 硬报 connected，
    // 于是 UI 显示「已连接」而中继侧什么都没收到，是最难查的一类假成功。
    if (msg == null || msg['ok'] != true) {
      return state.copyWith(
        relayUrl: relayUrl,
        relayDeviceId: deviceId,
        state: PrpConnectionState.error,
        errorMessage: '中继握手未完成（已注册，但自检回传失败）',
      );
    }
    final echo = msg['relay_says'] as String? ?? msg['echo'] as String?;

    return state.copyWith(
      // mode 不清 idle 的话 PrpState.isActive 仍是 false（见 :83），
      // UI 的「已连接」判定和 host/client 分支都会落错。
      mode: PrpMode.client,
      relayUrl: relayUrl,
      relayDeviceId: deviceId,
      relayInstruction: instruction,
      relayLastEcho: echo,
      state: PrpConnectionState.connected,
      clearError: true,
    );
  }

  /// Per-request budget for the relay bridge.
  ///
  /// `HttpClient()` has no connection timeout by default, and a public host may
  /// blackhole packets — without this the UI sits in "connecting" until the OS
  /// gives up (minutes), which is exactly the symptom this guard removes.
  static const _relayTimeout = Duration(seconds: 10);

  Future<Map<String, dynamic>?> _relayPost(
    String url,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _logger.warning('Relay URL rejected (need http/https): $url');
      return null;
    }
    if (uri.isScheme('http')) {
      // The self-check payload discloses transport capabilities and device id.
      _logger.warning('Relay URL uses plain HTTP — payload is not encrypted: $url');
    }

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _relayTimeout;
      final req = await client.postUrl(uri).timeout(_relayTimeout);
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode(body));
      final resp = await req.close().timeout(_relayTimeout);
      if (resp.statusCode != 200) {
        _logger.warning('Relay POST $url -> ${resp.statusCode}');
        return null;
      }
      final data = await resp.transform(utf8.decoder).join().timeout(_relayTimeout);
      return jsonDecode(data) as Map<String, dynamic>;
    } on TimeoutException {
      _logger.warning('Relay POST timed out after ${_relayTimeout.inSeconds}s: $url');
    } catch (e, st) {
      _logger.warning('Relay POST failed: $e', e, st);
    } finally {
      client?.close(force: true);
    }
    return null;
  }
}

/// Clear the relay bridge connection state (mirrors StopHost pattern).
class DisconnectRelayAction extends ReduxAction<PrpService, PrpState> {
  @override
  PrpState reduce() {
    _logger.info('Disconnecting PRP from relay');
    // 必须走 clearRelay：四个字段传 null 在 copyWith 里等于"不改"。
    // mode 同时回 idle，否则 isActive 仍为 true。
    return state.copyWith(mode: PrpMode.idle, clearRelay: true);
  }
}
