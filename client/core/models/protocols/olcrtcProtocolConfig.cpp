#include "olcrtcProtocolConfig.h"

#include <QJsonDocument>
#include <QObject>
#include <QRegularExpression>

#include "core/utils/constants/configKeys.h"

namespace amnezia
{
    namespace
    {
        // Field names of the client config, shared by the persisted
        // "last_config" payload and olcrtc_config_data. Keys are snake_case to
        // match OlcrtcNative/Olcrtc.kt.
        constexpr QLatin1String keyProvider("provider");
        constexpr QLatin1String keyTransport("transport");
        constexpr QLatin1String keyRoomUrl("room_url");
        constexpr QLatin1String keyKey("key");
        constexpr QLatin1String keyDns("dns");
        constexpr QLatin1String keyProviderToken("provider_token");
    }

    const QStringList &OlcrtcProtocolConfig::validProviders()
    {
        static const QStringList providers { "jitsi", "telemost", "wbstream", "none" };
        return providers;
    }

    const QStringList &OlcrtcProtocolConfig::validTransports()
    {
        static const QStringList transports { "datachannel", "vp8channel", "seichannel", "videochannel" };
        return transports;
    }

    bool OlcrtcProtocolConfig::isValid(QString *error) const
    {
        if (!validProviders().contains(provider.trimmed().toLower())) {
            if (error) {
                *error = QObject::tr("Provider must be one of: %1").arg(validProviders().join(", "));
            }
            return false;
        }

        if (!validTransports().contains(transport.trimmed().toLower())) {
            if (error) {
                *error = QObject::tr("Transport must be one of: %1").arg(validTransports().join(", "));
            }
            return false;
        }

        if (roomUrl.trimmed().isEmpty()) {
            if (error) *error = QObject::tr("Room URL cannot be empty");
            return false;
        }

        const QString trimmedKey = key.trimmed();
        static const QRegularExpression hexRegex("^[0-9a-fA-F]{64}$");
        if (!hexRegex.match(trimmedKey).hasMatch()) {
            if (error) {
                *error = QObject::tr("Key must be exactly 64 hexadecimal characters (got %1)").arg(trimmedKey.length());
            }
            return false;
        }

        return true;
    }

    QJsonObject OlcrtcProtocolConfig::toClientJson() const
    {
        QJsonObject obj;
        obj[keyProvider] = provider.trimmed().toLower();
        obj[keyTransport] = transport.trimmed().toLower();
        obj[keyRoomUrl] = roomUrl.trimmed();
        obj[keyKey] = key.trimmed();
        obj[keyDns] = dns.trimmed();
        obj[keyProviderToken] = providerToken.trimmed();
        return obj;
    }

    OlcrtcProtocolConfig OlcrtcProtocolConfig::fromClientJson(const QJsonObject &json)
    {
        OlcrtcProtocolConfig cfg;
        cfg.provider = json.value(keyProvider).toString();
        cfg.transport = json.value(keyTransport).toString();
        cfg.roomUrl = json.value(keyRoomUrl).toString();
        cfg.key = json.value(keyKey).toString();
        cfg.dns = json.value(keyDns).toString();
        cfg.providerToken = json.value(keyProviderToken).toString();
        return cfg;
    }

    QJsonObject OlcrtcProtocolConfig::toJson() const
    {
        QJsonObject obj;
        obj[configKey::lastConfig] =
                QString::fromUtf8(QJsonDocument(toClientJson()).toJson(QJsonDocument::Compact));
        obj[configKey::isThirdPartyConfig] = isThirdPartyConfig;
        return obj;
    }

    OlcrtcProtocolConfig OlcrtcProtocolConfig::fromJson(const QJsonObject &json)
    {
        const QString lastConfigStr = json.value(configKey::lastConfig).toString();
        const QJsonDocument doc = QJsonDocument::fromJson(lastConfigStr.toUtf8());

        // Fall back to flat keys so a config written by an older build, which
        // stored the fields directly, still loads.
        OlcrtcProtocolConfig cfg = fromClientJson(doc.isObject() ? doc.object() : json);
        cfg.isThirdPartyConfig = json.value(configKey::isThirdPartyConfig).toBool(true);
        return cfg;
    }
} // namespace amnezia
