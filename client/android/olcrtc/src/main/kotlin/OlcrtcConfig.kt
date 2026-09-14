package org.amnezia.vpn.protocol.olcrtc

import org.amnezia.vpn.protocol.ProtocolConfig
import org.amnezia.vpn.util.net.InetNetwork

// The TUN MTU is a normal interface MTU. olcRTC carries the tunnel over a
// WebRTC session, so the payload MTU is handled inside libolcrtc and is
// unrelated to this value.
private const val OLCRTC_DEFAULT_MTU = 1500

class OlcrtcConfig protected constructor(
    protocolConfigBuilder: ProtocolConfig.Builder,
    val provider: String,
    val transport: String,
    val roomUrl: String,
    val key: String,
    val dns: String,
    val providerToken: String
) : ProtocolConfig(protocolConfigBuilder) {

    protected constructor(builder: Builder) : this(
        builder,
        builder.provider,
        builder.transport,
        builder.roomUrl,
        builder.key,
        builder.dns,
        builder.providerToken
    )

    class Builder : ProtocolConfig.Builder(false) {
        internal var provider: String = ""
            private set
        internal var transport: String = "datachannel"
            private set
        internal var roomUrl: String = ""
            private set
        internal var key: String = ""
            private set
        internal var dns: String = ""
            private set
        internal var providerToken: String = ""
            private set

        override var mtu: Int = OLCRTC_DEFAULT_MTU

        fun setProvider(provider: String) = apply { this.provider = provider }
        fun setTransport(transport: String) = apply { this.transport = transport }
        fun setRoomUrl(roomUrl: String) = apply { this.roomUrl = roomUrl }
        fun setKey(key: String) = apply { this.key = key }
        fun setDns(dns: String) = apply { this.dns = dns }
        fun setProviderToken(providerToken: String) = apply { this.providerToken = providerToken }

        override fun build(): OlcrtcConfig = configBuild().run { OlcrtcConfig(this@Builder) }
    }

    companion object {
        internal val DEFAULT_IPV4_ADDRESS: InetNetwork = InetNetwork("10.0.42.2", 30)

        inline fun build(block: Builder.() -> Unit): OlcrtcConfig = Builder().apply(block).build()
    }
}
