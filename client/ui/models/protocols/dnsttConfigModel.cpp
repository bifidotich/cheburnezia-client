#include "dnsttConfigModel.h"

#include <QJsonDocument>

#include <QHostAddress>
#include <QRegularExpression>
#include <QStringList>
#include <QUrl>
#include <QUrlQuery>

DnsttConfigModel::DnsttConfigModel(QObject *parent)
    : QObject(parent)
{
    m_config.resolvers = "https://1.1.1.1/dns-query";
    m_config.bootstrapIp = "";
}

QString DnsttConfigModel::domain() const
{
    return m_config.domain;
}

void DnsttConfigModel::setDomain(const QString &domain)
{
    if (m_config.domain != domain) {
        m_config.domain = domain;
        emit domainChanged();
        emit calculatedMtuChanged();
        emit isMtuValidChanged();
        emit isValidChanged();
    }
}

QString DnsttConfigModel::resolvers() const
{
    return m_config.resolvers;
}

void DnsttConfigModel::setResolvers(const QString &resolvers)
{
    if (m_config.resolvers != resolvers) {
        m_config.resolvers = resolvers;
        emit resolversChanged();
        emit isResolversValidChanged();
        emit needsBootstrapChanged();
        emit isValidChanged();
    }
}

QString DnsttConfigModel::bootstrapIp() const
{
    return m_config.bootstrapIp;
}

void DnsttConfigModel::setBootstrapIp(const QString &bootstrapIp)
{
    if (m_config.bootstrapIp != bootstrapIp) {
        m_config.bootstrapIp = bootstrapIp;
        emit bootstrapIpChanged();
        emit isValidChanged();
    }
}

QString DnsttConfigModel::publicKey() const
{
    return m_config.publicKey;
}

void DnsttConfigModel::setPublicKey(const QString &publicKey)
{
    if (m_config.publicKey != publicKey) {
        m_config.publicKey = publicKey;
        emit publicKeyChanged();
        emit isPublicKeyValidChanged();
        emit isValidChanged();
    }
}

int DnsttConfigModel::calculatedMtu() const
{
    return m_config.calculateMtu();
}

bool DnsttConfigModel::isMtuValid() const
{
    return m_config.calculateMtu() >= 80;
}

bool DnsttConfigModel::isPublicKeyValid() const
{
    static const QRegularExpression hexRegex("^[0-9a-fA-F]{64}$");
    return hexRegex.match(m_config.publicKey.trimmed()).hasMatch();
}

bool DnsttConfigModel::isResolversValid() const
{
    // An empty field is "not filled in yet", not "wrong": Save stays disabled
    // through isValid(), but no error is shown while the user is still typing.
    if (m_config.resolvers.trimmed().isEmpty()) {
        return true;
    }
    return amnezia::DnsttProtocolConfig::areResolversValid(m_config.resolvers);
}

QString DnsttConfigModel::resolversError() const
{
    if (m_config.resolvers.trimmed().isEmpty()) {
        return QString();
    }
    QString err;
    amnezia::DnsttProtocolConfig::areResolversValid(m_config.resolvers, &err);
    return err;
}

bool DnsttConfigModel::needsBootstrap() const
{
    // A bootstrap IP is needed as soon as any resolver is named rather than
    // given as a literal address: resolving that name would itself require the
    // tunnel that is not up yet.
    const QStringList specs = m_config.resolvers.split(',', Qt::SkipEmptyParts);
    for (const QString &rawSpec : specs) {
        QString spec = rawSpec.trimmed();
        if (spec.isEmpty()) {
            continue;
        }

        QString host;
        if (spec.startsWith("https://", Qt::CaseInsensitive)) {
            host = QUrl(spec).host();
        } else {
            const int schemeEnd = spec.indexOf("://");
            if (schemeEnd >= 0) {
                spec = spec.mid(schemeEnd + 3);
            }
            host = spec.section(':', 0, 0);
        }

        if (!host.isEmpty() && QHostAddress(host).isNull()) {
            return true;
        }
    }
    return false;
}

bool DnsttConfigModel::isValid() const
{
    return m_config.isValid();
}

QString DnsttConfigModel::getValidationError() const
{
    QString err;
    m_config.isValid(&err);
    return err;
}

QString DnsttConfigModel::generateUri() const
{
    QUrl url;
    url.setScheme("dnstt");
    url.setUserName(m_config.publicKey.trimmed());
    url.setHost(m_config.domain.trimmed());

    QUrlQuery query;
    query.addQueryItem("resolvers", m_config.resolvers.trimmed());
    if (!m_config.bootstrapIp.trimmed().isEmpty()) {
        query.addQueryItem("bootstrap", m_config.bootstrapIp.trimmed());
    }
    url.setQuery(query);
    return url.toString();
}

void DnsttConfigModel::updateModel(amnezia::DockerContainer container, const amnezia::DnsttProtocolConfig &protocolConfig)
{
    Q_UNUSED(container);

    m_config = protocolConfig;

    emit domainChanged();
    emit resolversChanged();
    emit bootstrapIpChanged();
    emit publicKeyChanged();
    emit calculatedMtuChanged();
    emit isMtuValidChanged();
    emit isPublicKeyValidChanged();
    emit isResolversValidChanged();
    emit needsBootstrapChanged();
    emit isValidChanged();
}

void DnsttConfigModel::updateModel(const QJsonObject &config)
{
    updateModel(amnezia::DockerContainer::Dnstt, amnezia::DnsttProtocolConfig::fromJson(config));
}

amnezia::DnsttProtocolConfig DnsttConfigModel::getProtocolConfig() const
{
    amnezia::DnsttProtocolConfig cfg = m_config;
    cfg.domain = cfg.domain.trimmed();
    cfg.resolvers = cfg.resolvers.trimmed();
    cfg.bootstrapIp = cfg.bootstrapIp.trimmed();
    cfg.publicKey = cfg.publicKey.trimmed();
    return cfg;
}

QJsonObject DnsttConfigModel::getConfig() const
{
    return getProtocolConfig().toJson();
}
