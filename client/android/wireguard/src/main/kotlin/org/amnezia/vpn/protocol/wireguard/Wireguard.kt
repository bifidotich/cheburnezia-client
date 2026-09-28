package org.amnezia.vpn.protocol.wireguard

import android.net.VpnService.Builder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.amnezia.awg.GoBackend
import org.amnezia.vpn.protocol.Protocol
import org.amnezia.vpn.protocol.ProtocolState.CONNECTED
import org.amnezia.vpn.protocol.ProtocolState.DISCONNECTED
import org.amnezia.vpn.protocol.ProtocolState.RECONNECTING
import org.amnezia.vpn.protocol.Statistics
import org.amnezia.vpn.protocol.VpnException
import org.amnezia.vpn.protocol.VpnStartException
import org.amnezia.vpn.util.LibraryLoader.loadSharedLibrary
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.asSequence
import org.amnezia.vpn.util.net.InetEndpoint
import org.amnezia.vpn.util.net.InetNetwork
import org.amnezia.vpn.util.net.parseInetAddress
import org.amnezia.vpn.util.optStringOrNull
import org.json.JSONObject

private const val TAG = "Wireguard"

// Dead tunnel detection. The awg-go backend keeps one UDP socket (and source port) for the
// lifetime of the tunnel, so once a carrier NAT/DPI drops that flow handshakes never
// succeed again, while the underlying network stays the same and no network change
// reconnect happens. Recreating the tunnel opens a new socket.
private const val WATCHDOG_INTERVAL_MS = 10_000L
// consecutive failed samples before the tunnel is considered dead
private const val WATCHDOG_STRIKES = 3
// wireguard REJECT_AFTER_TIME: keys older than this cannot be used, so while traffic flows
// a healthy tunnel always has a younger handshake
private const val DEFAULT_REJECT_AFTER_TIME_SEC = 180L
private const val RETRY_BACKOFF_BASE_SEC = 30L
private const val RETRY_BACKOFF_MAX_SEC = 300L

open class Wireguard : Protocol() {

    private var tunnelHandle: Int = -1
    private var config: WireguardConfig? = null // save config for reconnect
    protected open val ifName: String = "amn0"
    private lateinit var scope: CoroutineScope
    private var statusJob: Job? = null
    private var watchdogJob: Job? = null
    // watchdog reconnects in a row that did not bring a handshake back
    private var failedReconnects = 0

    override val statistics: Statistics
        get() {
            if (tunnelHandle == -1) return Statistics.EMPTY_STATISTICS
            val config = GoBackend.awgGetConfig(tunnelHandle) ?: return Statistics.EMPTY_STATISTICS
            return Statistics.build {
                var optsCount = 0
                config.splitToSequence("\n").forEach { line ->
                    with(line) {
                        when {
                            startsWith("rx_bytes=") -> setRxBytes(substring(9).toLong()).also { ++optsCount }
                            startsWith("tx_bytes=") -> setTxBytes(substring(9).toLong()).also { ++optsCount }
                            else -> {}
                        }
                    }
                    if (optsCount == 2) return@forEach
                }
            }
        }

    override fun internalInit() {
        if (!isInitialized) loadSharedLibrary(context, "wg-go")
        if (this::scope.isInitialized) {
            scope.cancel()
        }
        scope = CoroutineScope(Dispatchers.IO)
    }

    override suspend fun startVpn(config: JSONObject, vpnBuilder: Builder, protect: (Int) -> Boolean) {
        val wireguardConfig = parseConfig(config)
        start(wireguardConfig, vpnBuilder, protect)
        this.config = wireguardConfig
    }

    protected open fun parseConfig(config: JSONObject): WireguardConfig {
        val configData = config.getJSONObject("wireguard_config_data")
        return WireguardConfig.build {
            configWireguard(config, configData)
            configSplitTunneling(config)
            configAppSplitTunneling(config)
        }
    }

    protected fun WireguardConfig.Builder.configWireguard(config: JSONObject, configData: JSONObject) {
        configData.getString("client_ip").split(",").map { address ->
            InetNetwork.parse(address.trim())
        }.forEach(::addAddress)

        config.optStringOrNull("dns1")?.let { dns ->
            addDnsServer(parseInetAddress(dns.trim()))
        }

        config.optStringOrNull("dns2")?.let { dns ->
            addDnsServer(parseInetAddress(dns.trim()))
        }

        val defRoutes = hashSetOf(
            InetNetwork("0.0.0.0", 0),
            InetNetwork("::", 0)
        )
        val routes = hashSetOf<InetNetwork>()
        configData.getJSONArray("allowed_ips").asSequence<String>().map { route ->
            InetNetwork.parse(route.trim())
        }.forEach(routes::add)
        // if the allowed IPs list contains at least one non-default route, disable global split tunneling
        if (routes.any { it !in defRoutes }) disableSplitTunneling()
        addRoutes(routes)

        configData.optStringOrNull("mtu")?.let { setMtu(it.toInt()) }

        val host = configData.getString("hostName").let { parseInetAddress(it.trim()) }
        val port = configData.getInt("port")
        setEndpoint(InetEndpoint(host, port))

        if (configData.optBoolean("isObfuscationEnabled")) {
            setUseProtocolExtension(true)
            configExtensionParameters(configData)
        }

        configData.optStringOrNull("persistent_keep_alive")?.let { setPersistentKeepalive(it) }
        configData.getString("client_priv_key").let { setPrivateKeyHex(it.base64ToHex()) }
        configData.getString("server_pub_key").let { setPublicKeyHex(it.base64ToHex()) }
        configData.optStringOrNull("psk_key")?.let { setPreSharedKeyHex(it.base64ToHex()) }
    }

    protected fun WireguardConfig.Builder.configExtensionParameters(configData: JSONObject) {
        configData.optStringOrNull("Jc")?.let { setJc(it.toInt()) }
        configData.optStringOrNull("Jmin")?.let { setJmin(it.toInt()) }
        configData.optStringOrNull("Jmax")?.let { setJmax(it.toInt()) }
        configData.optStringOrNull("S1")?.let { setS1(it.toInt()) }
        configData.optStringOrNull("S2")?.let { setS2(it.toInt()) }
        configData.optStringOrNull("S3")?.let { setS3(it.toInt()) }
        configData.optStringOrNull("S4")?.let { setS4(it.toInt()) }
        configData.optStringOrNull("H1")?.trim()?.let { if (it.isNotEmpty()) setH1(it) }
        configData.optStringOrNull("H2")?.trim()?.let { if (it.isNotEmpty()) setH2(it) }
        configData.optStringOrNull("H3")?.trim()?.let { if (it.isNotEmpty()) setH3(it) }
        configData.optStringOrNull("H4")?.trim()?.let { if (it.isNotEmpty()) setH4(it) }
        configData.optStringOrNull("I1")?.let { setI1(it) }
        configData.optStringOrNull("I2")?.let { setI2(it) }
        configData.optStringOrNull("I3")?.let { setI3(it) }
        configData.optStringOrNull("I4")?.let { setI4(it) }
        configData.optStringOrNull("I5")?.let { setI5(it) }
        configData.optStringOrNull("HeaderProtectionKey")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setHeaderProtectionKey(it.base64ToHex()) }
        configData.optStringOrNull("ContentPaddingAddition")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setContentPaddingAddition(it) }
        configData.optStringOrNull("RekeyAfterTime")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setRekeyAfterTime(it) }
        configData.optStringOrNull("RekeyTimeout")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setRekeyTimeout(it) }
        configData.optStringOrNull("RejectAfterTime")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setRejectAfterTime(it) }
        configData.optStringOrNull("KeepaliveTimeout")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setKeepaliveTimeout(it) }
        configData.optStringOrNull("MaxHandshakeAttempts")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setMaxHandshakeAttempts(it) }
        configData.optStringOrNull("RandomTrailers")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setRandomTrailers(it) }
        configData.optStringOrNull("DisableCookies")?.trim()?.takeIf { it.isNotEmpty() }
            ?.let { setDisableCookies(it) }
    }

    private fun start(
        config: WireguardConfig,
        vpnBuilder: Builder,
        protect: (Int) -> Boolean,
        stopExistingVpn: Boolean = false
    ) {
        if (!stopExistingVpn && tunnelHandle != -1) {
            Log.w(TAG, "Tunnel already up")
            return
        }

        buildVpnInterface(config, vpnBuilder)

        vpnBuilder.establish().use { tunFd ->
            if (stopExistingVpn && tunnelHandle != -1) {
                turnOffVpn()
            }
            if (tunFd == null) {
                throw VpnStartException("Create VPN interface: permission not granted or revoked")
            }
            Log.i(TAG, "awg-go backend ${GoBackend.awgVersion()}")
            tunnelHandle = GoBackend.awgTurnOn(ifName, tunFd.detachFd(), config.toWgUserspaceString())
        }

        if (tunnelHandle < 0) {
            tunnelHandle = -1
            throw VpnStartException("Wireguard tunnel creation error")
        }

        if (!protect(GoBackend.awgGetSocketV4(tunnelHandle)) || !protect(GoBackend.awgGetSocketV6(tunnelHandle))) {
            GoBackend.awgTurnOff(tunnelHandle)
            tunnelHandle = -1
            throw VpnStartException("Protect VPN interface: permission not granted or revoked")
        }
        launchStatusJob()
        launchWatchdogJob(config)
    }

    private fun launchStatusJob() {
        Log.d(TAG, "Launch status job")
        statusJob = scope.launch {
            while (true) {
                val lastHandshake = getLastHandshake()
                Log.v(TAG, "lastHandshake=$lastHandshake")
                if (lastHandshake == 0L) {
                    delay(1000)
                    continue
                }
                if (lastHandshake == -2L || lastHandshake > 0L) state.value = CONNECTED
                else if (lastHandshake == -1L) state.value = DISCONNECTED
                statusJob = null
                break
            }
        }
    }

    private fun launchWatchdogJob(config: WireguardConfig) {
        val rejectAfterTime = config.rejectAfterTime?.trim()?.toLongOrNull() ?: DEFAULT_REJECT_AFTER_TIME_SEC
        val tunnelStartTime = currentTimeSec()
        watchdogJob = scope.launch {
            var prev: TunnelStats? = null
            var strikes = 0
            while (true) {
                delay(WATCHDOG_INTERVAL_MS)
                val stats = getTunnelStats() ?: continue
                val now = currentTimeSec()
                val handshakeAge = now - stats.lastHandshake
                if (stats.lastHandshake > 0 && handshakeAge < rejectAfterTime) failedReconnects = 0

                val stale = if (stats.lastHandshake > 0) {
                    handshakeAge > rejectAfterTime
                } else {
                    // no handshake since the previous watchdog reconnect: retry with backoff
                    state.value == RECONNECTING && now - tunnelStartTime > retryBackoff()
                }
                // packets are sent, but nothing comes back
                val oneWay = prev != null && stats.txBytes > prev.txBytes && stats.rxBytes == prev.rxBytes
                prev = stats

                strikes = if (stale && oneWay) strikes + 1 else 0
                if (strikes < WATCHDOG_STRIKES) continue

                Log.w(TAG, "Tunnel looks dead: lastHandshake=${stats.lastHandshake}, " +
                    "failedReconnects=$failedReconnects, reconnecting")
                ++failedReconnects
                watchdogJob = null
                requestReconnect()
                break
            }
        }
    }

    private fun retryBackoff(): Long =
        (RETRY_BACKOFF_BASE_SEC shl (failedReconnects - 1).coerceIn(0, 4)).coerceAtMost(RETRY_BACKOFF_MAX_SEC)

    private fun currentTimeSec(): Long = System.currentTimeMillis() / 1000

    private class TunnelStats(val lastHandshake: Long, val rxBytes: Long, val txBytes: Long)

    private fun getTunnelStats(): TunnelStats? {
        if (tunnelHandle == -1) return null
        val config = GoBackend.awgGetConfig(tunnelHandle) ?: return null
        var lastHandshake: Long? = null
        var rxBytes: Long? = null
        var txBytes: Long? = null
        config.lineSequence().forEach { line ->
            when {
                line.startsWith("last_handshake_time_sec=") -> lastHandshake = line.substring(24).toLongOrNull()
                line.startsWith("rx_bytes=") -> rxBytes = line.substring(9).toLongOrNull()
                line.startsWith("tx_bytes=") -> txBytes = line.substring(9).toLongOrNull()
            }
        }
        return TunnelStats(lastHandshake ?: return null, rxBytes ?: return null, txBytes ?: return null)
    }

    private fun getLastHandshake(): Long {
        if (tunnelHandle == -1) {
            Log.e(TAG, "Trying to get config of a non-existent tunnel")
            return -1
        }
        val config = GoBackend.awgGetConfig(tunnelHandle)
        if (config == null) {
            Log.e(TAG, "Failed to get tunnel config")
            return -2
        }
        val lastHandshake = config.lines().find { it.startsWith("last_handshake_time_sec=") }?.substring(24)?.toLong()
        if (lastHandshake == null) {
            Log.e(TAG, "Failed to get last_handshake_time_sec")
            return -2
        }
        return lastHandshake
    }

    private fun turnOffVpn() {
        statusJob?.cancel()
        statusJob = null
        watchdogJob?.cancel()
        watchdogJob = null
        val handleToClose = tunnelHandle
        tunnelHandle = -1
        GoBackend.awgTurnOff(handleToClose)
    }

    override fun stopVpn() {
        if (tunnelHandle == -1) {
            Log.w(TAG, "Tunnel already down")
            return
        }
        turnOffVpn()
        state.value = DISCONNECTED
    }

    override fun reconnectVpn(vpnBuilder: Builder, protect: (Int) -> Boolean) {
        val config = this.config ?: throw VpnException("Reconnect config is empty")
        start(config, vpnBuilder, protect, true)
    }
}
