package org.localsend.localsend_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * PRP (Peer Relay Protocol) - Hotspot Relay Plugin for Android
 *
 * Enables devices to establish a temporary local network via WiFi hotspot
 * when they cannot discover each other on the same LAN.
 *
 * Two modes:
 *   HOTSPOT_HOST - Device creates a local-only hotspot and waits for peers
 *   HOTSPOT_CLIENT - Device scans QR and connects to the host's hotspot
 */
class HotspotRelayPlugin(private val activity: MainActivity) {

    companion object {
        private const val TAG = "HotspotRelayPlugin"
        private const val CHANNEL = "org.localsend.localsend_app/hotspot_relay"

        // Intent actions for hotspot state changes
        private const val ACTION_HOTSPOT_STATE_CHANGED =
            "android.net.wifi.WIFI_AP_STATE_CHANGED"

        // Timeout for ConnectivityManager.requestNetwork. A request that never
        // resolves leaks its callback until the per-app limit is hit.
        private const val REQUEST_NETWORK_TIMEOUT_MS = 30_000
    }

    private var wifiManager: WifiManager? = null
    private var connectivityManager: ConnectivityManager? = null

    /// Result of a hotspot start call that has not completed yet.
    /// Guarded: a second start while one is pending replies BUSY instead of
    /// overwriting the pending result (which would hang the Dart side).
    private var pendingStartResult: MethodChannel.Result? = null

    /// Sink for pushing hotspot lifecycle events to Dart.
    private var eventSink: EventChannel.EventSink? = null

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var hotspotStateReceiver: BroadcastReceiver? = null
    private var hotspotReservation: WifiManager.LocalOnlyHotspotReservation? = null

    /**
     * Register this plugin's method channel on the given Flutter engine.
     */
    fun configure(flutterEngine: FlutterEngine) {
        val context = activity.applicationContext
        wifiManager = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startHotspot" -> startHotspot(result)
                "stopHotspot" -> stopHotspot(result)
                "isHotspotActive" -> isHotspotActive(result)
                "connectToWifi" -> connectToWifi(call, result)
                "disconnectWifi" -> disconnectWifi(result)
                "isConnectedToHotspot" -> isConnectedToHotspot(result)
                "getHotspotInfo" -> getHotspotInfo(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "${CHANNEL}_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    /// Push a hotspot lifecycle event to Dart (must be called on main thread).
    private fun notifyEvent(name: String) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(mapOf("event" to name))
        }
    }

    // ============================================================
    //  HOTSPOT HOST MODE
    // ============================================================

    /**
     * Start a local-only hotspot.
     *
     * On Android 8.0+ (API 26+), uses [WifiManager.startLocalOnlyHotspot]
     * which creates a secure hotspot without internet access.
     *
     * On older devices, falls back to [WifiManager.setWifiApEnabled] (requires
     * system permission on some devices).
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun startHotspot(result: MethodChannel.Result) {
        Log.d(TAG, "startHotspot called")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("UNSUPPORTED", "Hotspot relay requires Android 8.0+", null)
            return
        }

        // Guard against concurrent starts: replying to the pending result
        // must never be skipped, or Dart awaits forever.
        if (pendingStartResult != null) {
            result.error("BUSY", "Hotspot start already in progress", null)
            return
        }

        // Check if hotspot is already running
        if (isHotspotRunning()) {
            Log.d(TAG, "Hotspot already running, returning current info")
            val info = getCurrentHotspotInfo()
            if (info != null) {
                result.success(info)
            } else {
                result.error("ALREADY_RUNNING", "Hotspot is already running but info unavailable", null)
            }
            return
        }

        try {
            val wifiManager = wifiManager ?: run {
                result.error("NO_WIFI_SERVICE", "WiFi service unavailable", null)
                return
            }

            pendingStartResult = result

            // startLocalOnlyHotspot is the right call on every API level we
            // ship (26+). The previous 13/Tiramisu branch only forwarded to
            // this same method, so it was deleted rather than kept as a
            // misleading placeholder for a SoftApConfiguration path we do not use.
            startLocalOnlyHotspot(wifiManager)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start hotspot", e)
            pendingStartResult = null
            result.error("HOTSPOT_ERROR", "Failed to start hotspot: ${e.message}", null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun startLocalOnlyHotspot(wifiManager: WifiManager) {
        // Public signature: startLocalOnlyHotspot(LocalOnlyHotspotCallback callback, Handler handler)
        wifiManager.startLocalOnlyHotspot(
            object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    Log.d(TAG, "LocalOnlyHotspot started")

                    // Reply exactly once. Taking the pending result and nulling
                    // it in the same step means a late onStopped/onFailed can
                    // never reply a second time (which would throw
                    // IllegalStateException "Reply already submitted").
                    val pending = pendingStartResult
                    pendingStartResult = null

                    if (pending == null) {
                        // The start was abandoned before the OS called back
                        // (stopHotspot replied first). Never leave an orphan
                        // hotspot running behind the user's back.
                        Log.w(TAG, "Hotspot started after the start was abandoned; closing it")
                        // close() is API 26, same level as startLocalOnlyHotspot.
                        try {
                            reservation.close()
                        } catch (e: Exception) {
                            Log.w(TAG, "Error closing orphaned reservation", e)
                        }
                        return
                    }

                    // Keep the reservation alive to prevent hotspot from stopping
                    hotspotReservation = reservation

                    val config = reservation.wifiConfiguration
                    val ssid = config?.SSID?.trim('"') ?: "LocalSend-Relay"
                    val password = config?.preSharedKey?.trim('"') ?: ""

                    Log.d(TAG, "Hotspot SSID: $ssid, Password: $password")

                    // Return hotspot info to Flutter. The AP address may not be
                    // assigned yet at this point; Flutter re-reads it through
                    // getHotspotInfo when it comes back empty.
                    val info = mapOf(
                        "ssid" to ssid,
                        "password" to password,
                        "isRunning" to true,
                        "ipAddress" to findHotspotIp(),
                    )
                    pending.success(info)

                    // Register broadcast receiver to monitor hotspot state
                    registerHotspotStateReceiver(reservation)
                }

                override fun onStopped() {
                    Log.d(TAG, "LocalOnlyHotspot stopped")
                    // If a start was still pending, it can never succeed now.
                    val pending = pendingStartResult
                    pendingStartResult = null
                    pending?.error("HOTSPOT_STOPPED", "Hotspot stopped before start completed", null)
                    // Notify Dart so the UI does not stay in a fake "connected" state.
                    notifyEvent("hotspotStopped")
                }

                override fun onFailed(reason: Int) {
                    Log.e(TAG, "LocalOnlyHotspot failed, reason: $reason")
                    val errorMsg = when (reason) {
                        WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL ->
                            "No channel available"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_GENERIC ->
                            "Generic hotspot error"
                        WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE ->
                            "Incompatible mode (tethering already active)"
                        else -> "Unknown error (code: $reason)"
                    }
                    val pending = pendingStartResult
                    pendingStartResult = null
                    pending?.error("HOTSPOT_FAILED", errorMsg, null)
                }
            },
            Handler(Looper.getMainLooper()),
        )
    }

    /**
     * Stop the current hotspot.
     */
    private fun stopHotspot(result: MethodChannel.Result) {
        Log.d(TAG, "stopHotspot called")

        // If a start is still pending, reply to it before tearing down,
        // otherwise the Dart side would await forever.
        pendingStartResult?.let {
            it.error("STOPPED", "Hotspot start aborted by stopHotspot", null)
        }
        pendingStartResult = null

        // Close the reservation to stop the hotspot
        try {
            hotspotReservation?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing hotspot reservation", e)
        }
        hotspotReservation = null

        unregisterHotspotStateReceiver()
        unregisterNetworkCallback()
        // Detach the process from the hotspot network. Without this the whole
        // app keeps routing through a network that no longer exists, so the
        // regular LocalSend transfer (plain LAN) breaks until process restart.
        unbindProcessNetwork()

        result.success(mapOf("stopped" to true))
    }

    /**
     * Check if the hotspot is currently active.
     */
    private fun isHotspotActive(result: MethodChannel.Result) {
        result.success(isHotspotRunning())
    }

    /**
     * Get current hotspot info (SSID, password, etc.)
     */
    private fun getHotspotInfo(result: MethodChannel.Result) {
        val info = getCurrentHotspotInfo()
        if (info != null) {
            result.success(info)
        } else {
            result.success(mapOf(
                "ssid" to "",
                "password" to "",
                "isRunning" to false,
            ))
        }
    }

    // ============================================================
    //  HOTSPOT CLIENT MODE
    // ============================================================

    /**
     * Connect to a WiFi network (peer's hotspot).
     *
     * On Android 10+ (API 29+), uses [WifiNetworkSpecifier] for a
     * seamless connection experience.
     *
     * On older devices, uses [WifiManager] to configure and connect.
     */
    private fun connectToWifi(call: MethodCall, result: MethodChannel.Result) {
        val ssid = call.argument<String>("ssid") ?: ""
        val password = call.argument<String>("password") ?: ""

        Log.d(TAG, "connectToWifi: SSID=$ssid")

        if (ssid.isEmpty()) {
            result.error("INVALID_SSID", "SSID cannot be empty", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                connectToWifiAndroid10(ssid, password, result)
            } else {
                connectToWifiLegacy(ssid, password, result)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to connect to WiFi", e)
            result.error("CONNECT_ERROR", "Failed to connect: ${e.message}", null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun connectToWifiAndroid10(
        ssid: String,
        password: String,
        result: MethodChannel.Result
    ) {
        // setWpa2Passphrase throws for anything outside 8..63 chars, which
        // would surface as an opaque CONNECT_ERROR. Validate up front instead.
        val specifierBuilder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isEmpty()) {
            specifierBuilder.setIsEnhancedOpen(true)
        } else if (password.length in 8..63) {
            specifierBuilder.setWpa2Passphrase(password)
        } else {
            result.error(
                "INVALID_PASSWORD",
                "WiFi password must be 8-63 characters (got ${password.length})",
                null,
            )
            return
        }
        val specifier = specifierBuilder.build()

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        val cm = connectivityManager ?: run {
            result.error("NO_CONNECTIVITY", "Connectivity service unavailable", null)
            return
        }

        // Register a network callback to track connection progress
        val callback = object : ConnectivityManager.NetworkCallback() {
            // onAvailable and onUnavailable can both fire on some OEM stacks;
            // replying twice throws IllegalStateException.
            private var replied = false

            private fun replyOnce(block: () -> Unit) {
                if (replied) return
                replied = true
                block()
            }

            override fun onAvailable(network: Network) {
                Log.d(TAG, "Connected to hotspot network: $network")
                // Attempt to bind to this network for discovery
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    cm.bindProcessToNetwork(network)
                }
                replyOnce {
                    // The gateway of a local-only hotspot is the host device,
                    // which is the address the user needs to reach it.
                    result.success(
                        mapOf(
                            "connected" to true,
                            "ssid" to ssid,
                            "ipAddress" to resolveGatewayIp(cm, network),
                        )
                    )
                }
            }

            override fun onUnavailable() {
                Log.e(TAG, "Hotspot network unavailable")
                replyOnce {
                    result.error("CONNECT_UNAVAILABLE", "Could not connect to hotspot", null)
                }
            }

            override fun onLost(network: Network) {
                Log.d(TAG, "Lost hotspot network: $network")
                // Release the process binding and tell Dart. Without this the
                // UI keeps showing "connected" and the whole app stays pinned
                // to a network that is gone.
                unbindProcessNetwork()
                notifyEvent("hotspotStopped")
            }
        }

        networkCallback = callback
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Without a timeout, a request that never resolves keeps its
            // callback alive; Android caps callbacks around 100 per app and
            // requestNetwork starts throwing once that is exhausted.
            cm.requestNetwork(request, callback, REQUEST_NETWORK_TIMEOUT_MS)
        } else {
            cm.requestNetwork(request, callback)
        }
    }

    private fun connectToWifiLegacy(
        ssid: String,
        password: String,
        result: MethodChannel.Result
    ) {
        val wifiManager = wifiManager ?: run {
            result.error("NO_WIFI_SERVICE", "WiFi service unavailable", null)
            return
        }

        val wifiConfig = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            preSharedKey = "\"$password\""
            allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
        }

        // Remove existing configuration for this SSID
        val existingNetId = wifiManager.configuredNetworks
            .firstOrNull { it.SSID?.trim('"') == ssid }
            ?.networkId

        if (existingNetId != null) {
            wifiManager.removeNetwork(existingNetId)
        }

        val netId = wifiManager.addNetwork(wifiConfig)
        if (netId == -1) {
            result.error("CONNECT_FAILED", "Failed to add network configuration", null)
            return
        }

        val connected = wifiManager.enableNetwork(netId, true)
        if (connected) {
            wifiManager.reconnect()
            result.success(
                mapOf(
                    "connected" to true,
                    "ssid" to ssid,
                    "ipAddress" to findHotspotIp(),
                )
            )
        } else {
            result.error("CONNECT_FAILED", "Failed to enable network", null)
        }
    }

    /**
     * Disconnect from the current hotspot network.
     */
    private fun disconnectWifi(result: MethodChannel.Result) {
        Log.d(TAG, "disconnectWifi called")
        // unregisterNetworkCallback() already releases and nulls the callback,
        // so the second unregister block that used to follow it was dead code.
        unregisterNetworkCallback()
        // Must unbind, otherwise the process stays pinned to a dead hotspot
        // network and all other traffic (including plain LAN transfers) dies.
        unbindProcessNetwork()

        result.success(mapOf("disconnected" to true))
    }

    /**
     * Check if currently connected to the hotspot network.
     */
    private fun isConnectedToHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(false)
            return
        }

        val cm = connectivityManager
        val activeNetwork = cm?.activeNetwork ?: run {
            result.success(false)
            return
        }

        val caps = cm.getNetworkCapabilities(activeNetwork)
        val isWifi = caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        // Check if the network does NOT have internet (characteristic of local-only hotspot)
        val hasInternet = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true

        result.success(isWifi && !hasInternet)
    }

    // ============================================================
    //  HELPERS
    // ============================================================

    /**
     * WifiManager exposes no public API to query soft-AP / LocalOnlyHotspot state.
     * We therefore track our own reservation first, and only fall back to the hidden
     * `isWifiApEnabled` API via reflection. That fallback is blocked by the hidden-API
     * restrictions on API 28+, in which case this simply returns false.
     */
    private fun isHotspotRunning(): Boolean {
        if (hotspotReservation != null) {
            return true
        }
        return try {
            val method = wifiManager?.javaClass?.getMethod("isWifiApEnabled")
            method?.isAccessible = true
            method?.invoke(wifiManager) as? Boolean ?: false
        } catch (e: Exception) {
            Log.w(TAG, "Failed to check hotspot state", e)
            false
        }
    }

    /**
     * Address of this device on the WiFi AP interface it currently owns.
     *
     * LocalOnlyHotspot has no public getter for the AP address, so it is read
     * from the interface table. The AP side ends in .1 on the stacks seen so
     * far; when several site-local addresses exist that one wins.
     */
    private fun findHotspotIp(): String {
        return try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return ""
            val candidates = interfaces.asSequence()
                .filter { it.isUp && !it.isLoopback }
                .filterNot { isCellularInterface(it.name) }
                .flatMap { it.inetAddresses.asSequence() }
                .filterIsInstance<Inet4Address>()
                .filter { it.isSiteLocalAddress }
                .mapNotNull { it.hostAddress }
                .toList()
            candidates.firstOrNull { it.endsWith(".1") } ?: candidates.firstOrNull() ?: ""
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve hotspot IP", e)
            ""
        }
    }

    /**
     * Gateway of [network] — for a local-only hotspot that is the host device.
     * A hotspot without internet has no default route, so the interface scan is
     * the fallback rather than an exception path.
     */
    private fun resolveGatewayIp(cm: ConnectivityManager, network: Network): String {
        return try {
            val gateway = cm.getLinkProperties(network)
                ?.routes
                ?.firstOrNull { it.isDefaultRoute }
                ?.gateway
                ?.hostAddress
            gateway ?: findHotspotIp()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to resolve gateway IP", e)
            findHotspotIp()
        }
    }

    private fun isCellularInterface(name: String?): Boolean {
        val n = name ?: return false
        return n.startsWith("rmnet") || n.startsWith("ccmni") || n.startsWith("pdp") || n == "dummy0"
    }

    private fun getCurrentHotspotInfo(): Map<String, Any>? {
        // Preferred path: the configuration of the reservation we own (public API).
        hotspotReservation?.wifiConfiguration?.let { config ->
            return mapOf(
                "ssid" to (config.SSID?.trim('"') ?: ""),
                "password" to (config.preSharedKey?.trim('"') ?: ""),
                "isRunning" to true,
                "ipAddress" to findHotspotIp(),
            )
        }

        // Fallback: hidden WifiManager API via reflection.
        // WifiConfiguration exposes SSID / preSharedKey as public *fields*, not getters.
        return try {
            val getConfigMethod = wifiManager?.javaClass?.getMethod("getWifiApConfiguration")
            getConfigMethod?.isAccessible = true
            val config = getConfigMethod?.invoke(wifiManager)
            if (config != null) {
                val ssidField = config.javaClass.getField("SSID")
                val pskField = config.javaClass.getField("preSharedKey")
                mapOf(
                    "ssid" to ((ssidField.get(config) as? String)?.trim('"') ?: ""),
                    "password" to ((pskField.get(config) as? String)?.trim('"') ?: ""),
                    "isRunning" to isHotspotRunning(),
                    "ipAddress" to findHotspotIp(),
                )
            } else {
                null
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get hotspot info", e)
            null
        }
    }

    /**
     * Register a BroadcastReceiver to monitor hotspot state changes.
     * This is used to detect when the hotspot is turned off externally.
     */
    private fun registerHotspotStateReceiver(reservation: WifiManager.LocalOnlyHotspotReservation) {
        val filter = IntentFilter(ACTION_HOTSPOT_STATE_CHANGED)

        hotspotStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val state = intent.getIntExtra("wifi_state", 0)
                Log.d(TAG, "Hotspot state changed: $state")
                if (state == 10 || state == 11) { // WIFI_AP_STATE_DISABLING or DISABLED
                    // Hotspot was disabled externally
                    try {
                        reservation.close()
                    } catch (e: Exception) {
                        Log.w(TAG, "Error closing reservation", e)
                    }
                    hotspotReservation = null
                    // Notify Dart so the UI can leave the fake "connected" state.
                    notifyEvent("hotspotStopped")
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(hotspotStateReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            activity.registerReceiver(hotspotStateReceiver, filter)
        }
    }

    private fun unregisterHotspotStateReceiver() {
        try {
            hotspotStateReceiver?.let { activity.unregisterReceiver(it) }
            hotspotStateReceiver = null
        } catch (e: Exception) {
            Log.w(TAG, "Error unregistering hotspot receiver", e)
        }
    }

    private fun unregisterNetworkCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                networkCallback?.let {
                    connectivityManager?.unregisterNetworkCallback(it)
                }
                networkCallback = null
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering network callback", e)
            }
        }
    }

    /**
     * Release the process-wide binding installed by [connectToWifiAndroid10].
     *
     * `bindProcessToNetwork` is process-scoped, not transport-scoped: leaving it
     * set keeps every outgoing socket on a network that is about to disappear,
     * which silently breaks the app's regular LAN transfers.
     */
    private fun unbindProcessNetwork() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            connectivityManager?.bindProcessToNetwork(null)
        } catch (e: Exception) {
            Log.w(TAG, "Error unbinding process network", e)
        }
    }

    /**
     * Clean up all resources.
     */
    fun dispose() {
        try {
            hotspotReservation?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing hotspot reservation on dispose", e)
        }
        hotspotReservation = null
        pendingStartResult = null
        eventSink = null
        unregisterHotspotStateReceiver()
        unregisterNetworkCallback()
        unbindProcessNetwork()
    }
}
