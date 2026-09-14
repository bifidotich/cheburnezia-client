package org.amnezia.vpn.protocol.olcrtc

import android.net.VpnService.Builder
import org.amnezia.vpn.protocol.BadConfigException
import org.amnezia.vpn.protocol.Protocol
import org.amnezia.vpn.protocol.ProtocolState.CONNECTED
import org.amnezia.vpn.protocol.ProtocolState.DISCONNECTED
import org.amnezia.vpn.protocol.ProtocolState.RECONNECTING
import org.amnezia.vpn.protocol.Statistics
import org.amnezia.vpn.protocol.VpnStartException
import org.amnezia.vpn.util.LibraryLoader.loadSharedLibrary
import org.amnezia.vpn.util.Log
import org.amnezia.vpn.util.net.InetNetwork
import org.amnezia.vpn.util.net.parseInetAddress
import org.json.JSONObject

private const val TAG = "Olcrtc"

private val VALID_PROVIDERS = setOf("jitsi", "telemost", "wbstream", "none")
private val VALID_TRANSPORTS = setOf("datachannel", "vp8channel", "seichannel", "videochannel")

class Olcrtc : Protocol() {

    private var isRunning: Boolean = false
    override val statistics: Statistics = Statistics.EMPTY_STATISTICS

    override fun internalInit() {
        if (!isInitialized) {
            loadSharedLibrary(context, "olcrtc")
        }
    }

    override suspend fun startVpn(config: JSONObject, vpnBuilder: Builder, protect: (Int) -> Boolean) {
        if (isRunning) {
            Log.w(TAG, "olcRTC already running")
            return
        }

        val olcrtcConfigData = config.optJSONObject("olcrtc_config_data")
            ?: throw BadConfigException("olcrtc_config_data not found")

        val olcrtcConfig = parseConfig(config, olcrtcConfigData)
        start(olcrtcConfig, vpnBuilder, protect)
        state.value = CONNECTED
        isRunning = true
    }

    private fun parseConfig(config: JSONObject, olcrtcConfigData: JSONObject): OlcrtcConfig {
        return OlcrtcConfig.build {
            addAddress(OlcrtcConfig.DEFAULT_IPV4_ADDRESS)

            config.optString("dns1").let {
                if (it.isNotBlank()) addDnsServer(parseInetAddress(it))
            }
            config.optString("dns2").let {
                if (it.isNotBlank()) addDnsServer(parseInetAddress(it))
            }

            addRoute(InetNetwork("0.0.0.0", 0))
            addRoute(InetNetwork("2000::0", 3))

            // No route is excluded for the tunnel endpoint: olcRTC's WebRTC
            // sockets are kept outside the VPN via OlcrtcNative.protector.

            val provider = olcrtcConfigData.optString("provider").lowercase()
            if (provider !in VALID_PROVIDERS) {
                throw BadConfigException("olcRTC provider must be one of $VALID_PROVIDERS")
            }
            setProvider(provider)

            val transport = olcrtcConfigData.optString("transport").lowercase()
            if (transport !in VALID_TRANSPORTS) {
                throw BadConfigException("olcRTC transport must be one of $VALID_TRANSPORTS")
            }
            setTransport(transport)

            val roomUrl = olcrtcConfigData.optString("room_url")
            if (roomUrl.isBlank()) {
                throw BadConfigException("olcRTC room URL is empty")
            }
            setRoomUrl(roomUrl)

            val key = olcrtcConfigData.optString("key")
            if (key.length != 64) {
                throw BadConfigException("Invalid key (expected 64 hex characters)")
            }
            setKey(key)

            setDns(olcrtcConfigData.optString("dns", ""))
            setProviderToken(olcrtcConfigData.optString("provider_token", ""))

            configSplitTunneling(config)
            configAppSplitTunneling(config)
        }
    }

    private fun start(config: OlcrtcConfig, vpnBuilder: Builder, protect: (Int) -> Boolean) {
        buildVpnInterface(config, vpnBuilder)

        OlcrtcNative.protector = protect
        // libolcrtc reports its own liveness; reflect that in the UI instead of
        // staying CONNECTED after the session drops.
        OlcrtcNative.stateListener = { tunnelState ->
            when (tunnelState) {
                "connected" -> state.value = CONNECTED
                "reconnecting" -> state.value = RECONNECTING
                "disconnected" -> if (isRunning) state.value = DISCONNECTED
                else -> Log.w(TAG, "Unknown tunnel state: $tunnelState")
            }
        }

        vpnBuilder.establish().use { tunFd ->
            if (tunFd == null) {
                clearNativeHooks()
                throw VpnStartException("Create VPN interface: permission not granted or revoked")
            }

            Log.i(TAG, "Starting libolcrtc tunnel (provider: ${config.provider}, transport: ${config.transport})")
            // detachFd: libolcrtc owns the descriptor from here on and closes it
            // itself, so it must outlive this `use` block.
            val error = OlcrtcNative.startTunnel(
                tunFd.detachFd(),
                config.mtu,
                config.provider,
                config.transport,
                config.roomUrl,
                config.key,
                config.dns,
                config.providerToken
            )
            if (error != null) {
                clearNativeHooks()
                throw VpnStartException("Failed to start olcRTC tunnel: $error")
            }
        }
    }

    override fun stopVpn() {
        if (!isRunning) {
            return
        }

        try {
            OlcrtcNative.stopTunnel()?.let { Log.e(TAG, "Error stopping olcRTC tunnel: $it") }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping olcRTC tunnel: ${e.message}")
        } finally {
            clearNativeHooks()
        }

        state.value = DISCONNECTED
        isRunning = false
    }

    override fun reconnectVpn(vpnBuilder: Builder, protect: (Int) -> Boolean) {
        state.value = CONNECTED
    }

    private fun clearNativeHooks() {
        OlcrtcNative.protector = null
        OlcrtcNative.stateListener = null
    }

    companion object {
        val instance: Olcrtc by lazy { Olcrtc() }
    }
}
