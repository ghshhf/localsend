import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/network/prp_provider.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// PRP (Peer Relay Protocol) Page
///
/// Allows devices to establish a temporary local network via WiFi hotspot
/// for peer-to-peer file transfer when they are not on the same LAN.
class PrpPage extends StatefulWidget {
  const PrpPage({super.key});

  @override
  State<PrpPage> createState() => _PrpPageState();
}

class _PrpPageState extends State<PrpPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final PrpProvider _provider = PrpProvider();

  // Client mode form fields
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _provider.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onStateChanged);
    _provider.dispose();
    _tabController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PRP - Peer Relay'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.wifi_tethering), text: 'Host'),
            Tab(icon: Icon(Icons.wifi_find), text: 'Client'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHostTab(theme),
          _buildClientTab(theme),
        ],
      ),
    );
  }

  // ============================================================
  //  HOST TAB
  // ============================================================

  Widget _buildHostTab(ThemeData theme) {
    final isHosting = _provider.mode == PrpMode.host;
    final isConnected = _provider.state == PrpConnectionState.connected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status indicator
          _buildStatusCard(theme, isHosting, isConnected),

          const SizedBox(height: 16),

          if (isHosting && isConnected) ...[
            // QR Code showing hotspot connection info
            _buildQrCode(theme),

            const SizedBox(height: 16),

            // Connection info card
            _buildConnectionInfoCard(theme),

            const SizedBox(height: 16),

            // Stop host mode button
            _buildActionButton(
              theme: theme,
              label: 'Stop Hotspot',
              icon: Icons.stop_circle_outlined,
              color: theme.colorScheme.error,
              onPressed: () => _provider.stopHostMode(),
            ),
          ] else ...[
            // Start host mode button
            _buildActionButton(
              theme: theme,
              label: 'Start Hotspot Relay',
              icon: Icons.wifi_tethering,
              color: theme.colorScheme.primary,
              onPressed: () => _provider.startHostMode(),
            ),

            const SizedBox(height: 12),

            // Info text
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.primary, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Start a local WiFi hotspot so nearby devices can '
                      'connect and transfer files directly.\n\n'
                      'No internet connection required. '
                      'Data is transferred device-to-device only.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  //  CLIENT TAB
  // ============================================================

  Widget _buildClientTab(ThemeData theme) {
    final isClient = _provider.mode == PrpMode.client;
    final isConnected = _provider.state == PrpConnectionState.connected;
    final isLoading = _provider.state == PrpConnectionState.connecting;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Status indicator
          _buildStatusCard(theme, isClient, isConnected),

          const SizedBox(height: 16),

          if (isConnected) ...[
            // Connected state
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.wifi, size: 48,
                        color: theme.colorScheme.onPrimaryContainer),
                    const SizedBox(height: 8),
                    Text(
                      'Connected to ${_provider.hotspotInfo.ssid}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Open LocalSend to discover and transfer files.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            _buildActionButton(
              theme: theme,
              label: 'Disconnect',
              icon: Icons.wifi_off,
              color: theme.colorScheme.error,
              onPressed: () => _provider.disconnectFromPeer(),
            ),
          ] else ...[
            // Input form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Enter Hotspot Info',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),

                    // SSID input
                    TextField(
                      controller: _ssidController,
                      decoration: const InputDecoration(
                        labelText: 'Hotspot SSID',
                        prefixIcon: Icon(Icons.wifi),
                        border: OutlineInputBorder(),
                      ),
                      enabled: !isLoading,
                    ),

                    const SizedBox(height: 12),

                    // Password input
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(() =>
                              _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      obscureText: _obscurePassword,
                      enabled: !isLoading,
                    ),

                    const SizedBox(height: 16),

                    _buildActionButton(
                      theme: theme,
                      label: isLoading ? 'Connecting...' : 'Connect',
                      icon: isLoading ? Icons.hourglass_top : Icons.wifi_find,
                      color: theme.colorScheme.primary,
                      onPressed: (_ssidController.text.isNotEmpty &&
                              !isLoading)
                          ? () => _provider.connectToPeer(
                                ssid: _ssidController.text.trim(),
                                password: _passwordController.text.trim(),
                              )
                          : null,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Info text
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.primary, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Ask the other device to scan the QR code from the '
                      'Host tab, or manually enter the hotspot name and password.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),

            if (_provider.errorMessage != null) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _provider.errorMessage!,
                          style: TextStyle(
                              color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ============================================================
  //  REUSABLE WIDGETS
  // ============================================================

  Widget _buildStatusCard(
      ThemeData theme, bool isActive, bool isConnected) {
    return Card(
      color: isConnected
          ? theme.colorScheme.primaryContainer
          : isActive
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isConnected
                  ? Icons.check_circle
                  : isActive
                      ? Icons.hourglass_top
                      : Icons.info_outline,
              color: isConnected
                  ? theme.colorScheme.onPrimaryContainer
                  : isActive
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.onSurfaceVariant,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getStatusTitle(isActive, isConnected),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    _getStatusSubtitle(isActive, isConnected),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusTitle(bool isActive, bool isConnected) {
    if (isConnected) return 'Connected';
    if (isActive) return 'Connecting...';
    return 'Ready';
  }

  String _getStatusSubtitle(bool isActive, bool isConnected) {
    if (_provider.mode == PrpMode.host) {
      if (isConnected) return 'Hotspot active - share QR with peer';
      if (isActive) return 'Starting hotspot...';
      return 'Start a hotspot to enable peer relay';
    }
    if (_provider.mode == PrpMode.client) {
      if (isConnected) return 'Connected to peer hotspot';
      if (isActive) return 'Connecting to peer...';
      return 'Enter hotspot info to connect';
    }
    return 'Select a mode above';
  }

  Widget _buildQrCode(ThemeData theme) {
    // Encode hotspot connection info as URL-like string
    final connectionData = 'localsend://prp?ssid=${Uri.encodeComponent(_provider.hotspotInfo.ssid)}&password=${Uri.encodeComponent(_provider.hotspotInfo.password)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Scan to Connect',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              height: 220,
              child: PrettyQrView.data(
                errorCorrectLevel: QrErrorCorrectLevel.Q,
                data: connectionData,
                decoration: PrettyQrDecoration(
                  shape: PrettyQrSmoothSymbol(
                    roundFactor: 0,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan this QR with another LocalSend device',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionInfoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info, size: 20,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Connection Info',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow(theme, 'SSID', _provider.hotspotInfo.ssid),
            const SizedBox(height: 8),
            _infoRow(theme, 'Password', _provider.hotspotInfo.password),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              )),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied to clipboard')),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(value,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Icon(Icons.copy, size: 14,
                      color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required ThemeData theme,
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: theme.colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
