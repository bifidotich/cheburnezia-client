#include "olcrtcConfigModel.h"

#include <QJsonDocument>
#include <QRegularExpression>
#include <QUrl>
#include <QUrlQuery>

OlcrtcConfigModel::OlcrtcConfigModel(QObject *parent)
    : QObject(parent)
{
    m_config.provider = "jitsi";
    m_config.transport = "datachannel";
}

QString OlcrtcConfigModel::provider() const
{
    return m_config.provider;
}

void OlcrtcConfigModel::setProvider(const QString &provider)
{
    if (m_config.provider != provider) {
        m_config.provider = provider;
        emit providerChanged();
        emit isValidChanged();
    }
}

QString OlcrtcConfigModel::transport() const
{
    return m_config.transport;
}

void OlcrtcConfigModel::setTransport(const QString &transport)
{
    if (m_config.transport != transport) {
        m_config.transport = transport;
        emit transportChanged();
        emit isValidChanged();
    }
}

QString OlcrtcConfigModel::roomUrl() const
{
    return m_config.roomUrl;
}

void OlcrtcConfigModel::setRoomUrl(const QString &roomUrl)
{
    if (m_config.roomUrl != roomUrl) {
        m_config.roomUrl = roomUrl;
        emit roomUrlChanged();
        emit isValidChanged();
    }
}

QString OlcrtcConfigModel::key() const
{
    return m_config.key;
}

void OlcrtcConfigModel::setKey(const QString &key)
{
    if (m_config.key != key) {
        m_config.key = key;
        emit keyChanged();
        emit isKeyValidChanged();
        emit isValidChanged();
    }
}

QString OlcrtcConfigModel::dns() const
{
    return m_config.dns;
}

void OlcrtcConfigModel::setDns(const QString &dns)
{
    if (m_config.dns != dns) {
        m_config.dns = dns;
        emit dnsChanged();
    }
}

QString OlcrtcConfigModel::providerToken() const
{
    return m_config.providerToken;
}

void OlcrtcConfigModel::setProviderToken(const QString &providerToken)
{
    if (m_config.providerToken != providerToken) {
        m_config.providerToken = providerToken;
        emit providerTokenChanged();
    }
}

QStringList OlcrtcConfigModel::providers() const
{
    return amnezia::OlcrtcProtocolConfig::validProviders();
}

QStringList OlcrtcConfigModel::transports() const
{
    return amnezia::OlcrtcProtocolConfig::validTransports();
}

bool OlcrtcConfigModel::isKeyValid() const
{
    static const QRegularExpression hexRegex("^[0-9a-fA-F]{64}$");
    return hexRegex.match(m_config.key.trimmed()).hasMatch();
}

bool OlcrtcConfigModel::isValid() const
{
    return m_config.isValid();
}

QString OlcrtcConfigModel::getValidationError() const
{
    QString err;
    m_config.isValid(&err);
    return err;
}

QString OlcrtcConfigModel::generateUri() const
{
    QUrl url;
    url.setScheme("olcrtc");
    url.setUserName(m_config.key.trimmed());
    url.setHost(m_config.provider.trimmed().toLower());

    QUrlQuery query;
    query.addQueryItem("room", m_config.roomUrl.trimmed());
    query.addQueryItem("transport", m_config.transport.trimmed().toLower());
    if (!m_config.dns.trimmed().isEmpty()) {
        query.addQueryItem("dns", m_config.dns.trimmed());
    }
    if (!m_config.providerToken.trimmed().isEmpty()) {
        query.addQueryItem("token", m_config.providerToken.trimmed());
    }
    url.setQuery(query);
    return url.toString();
}

void OlcrtcConfigModel::updateModel(amnezia::DockerContainer container, const amnezia::OlcrtcProtocolConfig &protocolConfig)
{
    Q_UNUSED(container);

    m_config = protocolConfig;

    emit providerChanged();
    emit transportChanged();
    emit roomUrlChanged();
    emit keyChanged();
    emit dnsChanged();
    emit providerTokenChanged();
    emit isKeyValidChanged();
    emit isValidChanged();
}

void OlcrtcConfigModel::updateModel(const QJsonObject &config)
{
    updateModel(amnezia::DockerContainer::Olcrtc, amnezia::OlcrtcProtocolConfig::fromJson(config));
}

amnezia::OlcrtcProtocolConfig OlcrtcConfigModel::getProtocolConfig() const
{
    amnezia::OlcrtcProtocolConfig cfg = m_config;
    cfg.provider = cfg.provider.trimmed().toLower();
    cfg.transport = cfg.transport.trimmed().toLower();
    cfg.roomUrl = cfg.roomUrl.trimmed();
    cfg.key = cfg.key.trimmed();
    cfg.dns = cfg.dns.trimmed();
    cfg.providerToken = cfg.providerToken.trimmed();
    return cfg;
}

QJsonObject OlcrtcConfigModel::getConfig() const
{
    return getProtocolConfig().toJson();
}
