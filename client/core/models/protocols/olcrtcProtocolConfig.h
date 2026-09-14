#ifndef OLCRTCPROTOCOLCONFIG_H
#define OLCRTCPROTOCOLCONFIG_H

#include <QJsonObject>
#include <QString>
#include <QStringList>

namespace amnezia
{
    struct OlcrtcProtocolConfig
    {
        // Cover service: jitsi, telemost, wbstream or none. The WebRTC engine
        // is derived from it by olcRTC, so it is not stored here.
        QString provider;

        // How bytes are encoded onto the media session: datachannel,
        // vp8channel, seichannel or videochannel.
        QString transport;

        // Provider room URL or id both peers share.
        QString roomUrl;

        // 64-hex-digit (32-byte) shared tunnel key.
        QString key;

        // Optional resolver olcRTC uses for its own lookups.
        QString dns;

        // Optional pre-issued provider account token.
        QString providerToken;

        // olcRTC is only ever imported from a link; there is no server-side
        // container to install, so this is always a third-party config.
        bool isThirdPartyConfig = true;

        static const QStringList &validProviders();
        static const QStringList &validTransports();

        bool isValid(QString *error = nullptr) const;

        // Wire format handed to the Android layer as olcrtc_config_data.
        // Keys are snake_case to match OlcrtcNative/Olcrtc.kt.
        QJsonObject toClientJson() const;
        static OlcrtcProtocolConfig fromClientJson(const QJsonObject &json);

        // Persisted format, following the project convention of storing the
        // client config as a JSON string under "last_config".
        QJsonObject toJson() const;
        static OlcrtcProtocolConfig fromJson(const QJsonObject &json);
    };
} // namespace amnezia

#endif // OLCRTCPROTOCOLCONFIG_H
