package org.amnezia.vpn.protocol.olcrtc

import org.amnezia.vpn.util.Log

private const val TAG = "libolcrtc"

object OlcrtcNative {

    /**
     * VpnService.protect, installed by [Olcrtc] for the lifetime of a tunnel.
     * libolcrtc calls it through JNI before opening its WebRTC sockets (pion
     * ICE, provider HTTPS/WebSocket, DNS), so that its own traffic is not
     * routed back into the TUN.
     */
    @Volatile
    var protector: ((Int) -> Boolean)? = null

    /** Called from native code. Keep the name and signature in sync with jni_helper.c. */
    @JvmStatic
    fun protectSocket(fd: Int): Boolean = protector?.invoke(fd) ?: false

    /** Called from native code to surface libolcrtc's log output in logcat. */
    @JvmStatic
    fun nativeLog(message: String) = Log.i(TAG, message)

    /**
     * Tunnel state sink, installed by [Olcrtc] for the lifetime of a tunnel.
     * libolcrtc reports "connected", "reconnecting" and "disconnected" here so
     * the UI does not keep claiming a dead tunnel is up.
     */
    @Volatile
    var stateListener: ((String) -> Unit)? = null

    /** Called from native code. Keep the name and signature in sync with jni_helper.c. */
    @JvmStatic
    fun onStateChanged(state: String) {
        Log.i(TAG, "tunnel state: $state")
        stateListener?.invoke(state)
    }

    /**
     * Starts the tunnel on [tunFd], which native code takes ownership of.
     * Returns null on success, or a human-readable failure reason.
     */
    external fun startTunnel(
        tunFd: Int,
        tunMtu: Int,
        provider: String,
        transport: String,
        roomUrl: String,
        key: String,
        dns: String,
        providerToken: String
    ): String?

    /** Stops the tunnel. Returns null on success, or a failure reason. */
    external fun stopTunnel(): String?
}
