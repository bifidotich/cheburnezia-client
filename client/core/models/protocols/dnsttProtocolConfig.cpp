#include "dnsttProtocolConfig.h"

#include <QHostAddress>
#include <QJsonDocument>
#include <QObject>
#include <QRegularExpression>
#include <QStringList>
#include <QUrl>

#include "core/utils/constants/configKeys.h"

namespace amnezia
{
    namespace
    {
        // Field names of the client config, shared by the persisted
        // "last_config" payload and dnstt_config_data.
        constexpr QLatin1String keyDomain("domain");
        constexpr QLatin1String keyResolvers("resolvers");
        constexpr QLatin1String keyBootstrapIp("bootstrap_ip");
        constexpr QLatin1String keyPublicKey("public_key");

        // Smallest payload dnstt can operate on; mirrors libdnstt's minMtu.
        constexpr int minMtu = 80;

        // Deliberately no stricter than libdnstt's own resolver stack. A stored
        // config that the tunnel can use must never be refused here, because
        // InstallController treats an invalid DNSTT config as a hard error, so
        // only structurally broken names are rejected: IDN labels, underscores
        // and the trailing dot of a fully qualified name all stay valid.
        bool isValidHostOrIp(const QString &host)
        {
            if (host.isEmpty() || host.length() > 253) {
                return false;
            }
            if (!QHostAddress(host).isNull()) {
                return true;
            }

            QString name = host;
            if (name.endsWith('.')) {
                name.chop(1);
            }
            if (name.isEmpty()) {
                return false;
            }

            static const QString forbidden = QStringLiteral("/\\?#@:[]%\"'<>{}|^`");
            const QStringList labels = name.split('.');
            for (const QString &label : labels) {
                if (label.isEmpty() || label.length() > 63) {
                    return false;
                }
                if (label.startsWith('-') || label.endsWith('-')) {
                    return false;
                }
                for (const QChar &c : label) {
                    if (c.isSpace() || !c.isPrint() || forbidden.contains(c)) {
                        return false;
                    }
                }
            }
            return true;
        }

        // Splits "host", "host:port" and "[v6]:port". A bare IPv6 literal has
        // several colons and no port, so it is returned as the host.
        bool splitHostPort(const QString &hostPort, QString &host, QString &port)
        {
            port.clear();

            if (hostPort.startsWith('[')) {
                const int close = hostPort.indexOf(']');
                if (close < 0) {
                    return false;
                }
                host = hostPort.mid(1, close - 1);
                const QString rest = hostPort.mid(close + 1);
                if (rest.isEmpty()) {
                    return true;
                }
                if (!rest.startsWith(':')) {
                    return false;
                }
                port = rest.mid(1);
                return true;
            }

            const int colon = hostPort.lastIndexOf(':');
            if (colon < 0 || hostPort.count(':') > 1) {
                host = hostPort;
                return true;
            }
            host = hostPort.left(colon);
            port = hostPort.mid(colon + 1);
            return true;
        }

        // Mirrors buildTransport() in libdnstt: https:// is DoH, dot:// and
        // tls:// are DoT, anything else is plain UDP with an optional udp://
        // prefix. Rejecting malformed specs here keeps them from being stored
        // at all; otherwise the tunnel only fails at connect time, deep in a
        // log line, while the VPN interface still reports itself as up.
        bool isValidResolverSpec(const QString &rawSpec, QString *error)
        {
            const QString spec = rawSpec.trimmed();
            if (spec.isEmpty()) {
                if (error) *error = QObject::tr("Resolver cannot be empty");
                return false;
            }

            for (const QChar &c : spec) {
                if (c.isSpace()) {
                    if (error) {
                        *error = QObject::tr("Resolver \"%1\" contains a space").arg(spec);
                    }
                    return false;
                }
            }

            const QString lower = spec.toLower();

            if (lower.startsWith(QLatin1String("https://"))) {
                const QUrl url(spec);
                if (!url.isValid() || url.host().isEmpty() || !isValidHostOrIp(url.host())) {
                    if (error) *error = QObject::tr("\"%1\" is not a valid DoH URL").arg(spec);
                    return false;
                }
                return true;
            }

            QString hostPort = spec;
            if (lower.startsWith(QLatin1String("dot://")) || lower.startsWith(QLatin1String("tls://"))
                || lower.startsWith(QLatin1String("udp://"))) {
                hostPort = spec.mid(spec.indexOf(QLatin1String("://")) + 3);
            } else if (spec.contains(QLatin1String("://"))) {
                if (error) {
                    *error = QObject::tr("\"%1\" uses an unsupported scheme; use https://, dot:// or udp://").arg(spec);
                }
                return false;
            }

            QString host;
            QString port;
            if (!splitHostPort(hostPort, host, port) || !isValidHostOrIp(host)) {
                if (error) *error = QObject::tr("\"%1\" is not a valid resolver address").arg(spec);
                return false;
            }

            if (!port.isEmpty()) {
                bool ok = false;
                const int portNumber = port.toInt(&ok);
                if (!ok || portNumber < 1 || portNumber > 65535) {
                    if (error) *error = QObject::tr("\"%1\" has an invalid port").arg(spec);
                    return false;
                }
            }

            return true;
        }
    }

    int DnsttProtocolConfig::calculateMtu() const
    {
        const QString trimmedDomain = domain.trimmed();
        if (trimmedDomain.isEmpty()) {
            return 0;
        }

        // Names must be 255 octets or shorter in total length (RFC 1035
        // 2.3.4), minus the null terminator.
        int capacity = 255 - 1;
        const QStringList labels = trimmedDomain.split('.', Qt::SkipEmptyParts);
        for (const QString &label : labels) {
            // Subtract the length of the label and the length octet.
            capacity -= (label.length() + 1);
        }
        // Each label may be up to 63 bytes long but requires 64 to encode.
        capacity = (capacity * 63) / 64;
        // Base32 expands every 5 bytes to 8.
        capacity = (capacity * 5) / 8;

        // clientid + padding length prefix + padding + data length prefix
        const int numPadding = 3;
        const int mtu = capacity - 8 - 1 - numPadding - 1;
        return mtu > 0 ? mtu : 0;
    }

    bool DnsttProtocolConfig::areResolversValid(const QString &resolvers, QString *error)
    {
        const QStringList specs = resolvers.split(',', Qt::SkipEmptyParts);
        if (specs.isEmpty()) {
            if (error) *error = QObject::tr("Resolvers list cannot be empty");
            return false;
        }
        for (const QString &spec : specs) {
            if (!isValidResolverSpec(spec, error)) {
                return false;
            }
        }
        return true;
    }

    bool DnsttProtocolConfig::isValid(QString *error) const
    {
        if (domain.trimmed().isEmpty()) {
            if (error) *error = QObject::tr("Domain cannot be empty");
            return false;
        }

        const int mtu = calculateMtu();
        if (mtu < minMtu) {
            if (error) {
                *error = QObject::tr("Domain is too long: it leaves %1 bytes of payload, at least %2 are required")
                                 .arg(mtu)
                                 .arg(minMtu);
            }
            return false;
        }

        if (resolvers.trimmed().isEmpty()) {
            if (error) *error = QObject::tr("Resolvers list cannot be empty");
            return false;
        }

        if (!areResolversValid(resolvers, error)) {
            return false;
        }

        const QString key = publicKey.trimmed();
        static const QRegularExpression hexRegex("^[0-9a-fA-F]{64}$");
        if (!hexRegex.match(key).hasMatch()) {
            if (error) {
                *error = QObject::tr("Public key must be exactly 64 hexadecimal characters (got %1)").arg(key.length());
            }
            return false;
        }

        return true;
    }

    QJsonObject DnsttProtocolConfig::toClientJson() const
    {
        QJsonObject obj;
        obj[keyDomain] = domain.trimmed();
        obj[keyResolvers] = resolvers.trimmed();
        obj[keyBootstrapIp] = bootstrapIp.trimmed();
        obj[keyPublicKey] = publicKey.trimmed();
        return obj;
    }

    DnsttProtocolConfig DnsttProtocolConfig::fromClientJson(const QJsonObject &json)
    {
        DnsttProtocolConfig cfg;
        cfg.domain = json.value(keyDomain).toString();
        cfg.resolvers = json.value(keyResolvers).toString();
        cfg.bootstrapIp = json.value(keyBootstrapIp).toString();
        cfg.publicKey = json.value(keyPublicKey).toString();
        return cfg;
    }

    QJsonObject DnsttProtocolConfig::toJson() const
    {
        QJsonObject obj;
        obj[configKey::lastConfig] =
                QString::fromUtf8(QJsonDocument(toClientJson()).toJson(QJsonDocument::Compact));
        obj[configKey::isThirdPartyConfig] = isThirdPartyConfig;
        return obj;
    }

    DnsttProtocolConfig DnsttProtocolConfig::fromJson(const QJsonObject &json)
    {
        const QString lastConfigStr = json.value(configKey::lastConfig).toString();
        const QJsonDocument doc = QJsonDocument::fromJson(lastConfigStr.toUtf8());

        // Fall back to flat keys so a config written by an older build, which
        // stored the fields directly, still loads.
        DnsttProtocolConfig cfg = fromClientJson(doc.isObject() ? doc.object() : json);
        cfg.isThirdPartyConfig = json.value(configKey::isThirdPartyConfig).toBool(true);
        return cfg;
    }
} // namespace amnezia
