#ifndef DNSTTCONFIGMODEL_H
#define DNSTTCONFIGMODEL_H

#include <QJsonObject>
#include <QObject>
#include <QString>

#include "core/utils/containerEnum.h"
#include "core/models/protocols/dnsttProtocolConfig.h"

class DnsttConfigModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString domain READ domain WRITE setDomain NOTIFY domainChanged)
    Q_PROPERTY(QString resolvers READ resolvers WRITE setResolvers NOTIFY resolversChanged)
    Q_PROPERTY(QString bootstrapIp READ bootstrapIp WRITE setBootstrapIp NOTIFY bootstrapIpChanged)
    Q_PROPERTY(QString publicKey READ publicKey WRITE setPublicKey NOTIFY publicKeyChanged)
    Q_PROPERTY(int calculatedMtu READ calculatedMtu NOTIFY calculatedMtuChanged)
    Q_PROPERTY(bool isMtuValid READ isMtuValid NOTIFY isMtuValidChanged)
    Q_PROPERTY(bool isPublicKeyValid READ isPublicKeyValid NOTIFY isPublicKeyValidChanged)
    Q_PROPERTY(bool isResolversValid READ isResolversValid NOTIFY isResolversValidChanged)
    Q_PROPERTY(QString resolversError READ resolversError NOTIFY isResolversValidChanged)
    Q_PROPERTY(bool needsBootstrap READ needsBootstrap NOTIFY needsBootstrapChanged)
    Q_PROPERTY(bool isValid READ isValid NOTIFY isValidChanged)

public:
    explicit DnsttConfigModel(QObject *parent = nullptr);

    QString domain() const;
    void setDomain(const QString &domain);

    QString resolvers() const;
    void setResolvers(const QString &resolvers);

    QString bootstrapIp() const;
    void setBootstrapIp(const QString &bootstrapIp);

    QString publicKey() const;
    void setPublicKey(const QString &publicKey);

    int calculatedMtu() const;
    bool isMtuValid() const;
    bool isPublicKeyValid() const;
    bool isResolversValid() const;
    QString resolversError() const;
    bool needsBootstrap() const;
    bool isValid() const;

    Q_INVOKABLE QString getValidationError() const;
    Q_INVOKABLE QString generateUri() const;

public slots:
    // Loads the stored container config so the settings page shows the values
    // the tunnel is actually running with. The container argument is unused,
    // but keeps the signature uniform with the other protocol config models so
    // InstallUiController can drive them all the same way.
    void updateModel(amnezia::DockerContainer container, const amnezia::DnsttProtocolConfig &protocolConfig);
    void updateModel(const QJsonObject &config);

    amnezia::DnsttProtocolConfig getProtocolConfig() const;
    QJsonObject getConfig() const;

signals:
    void domainChanged();
    void resolversChanged();
    void bootstrapIpChanged();
    void publicKeyChanged();
    void calculatedMtuChanged();
    void isMtuValidChanged();
    void isPublicKeyValidChanged();
    void isResolversValidChanged();
    void needsBootstrapChanged();
    void isValidChanged();

private:
    amnezia::DnsttProtocolConfig m_config;
};

#endif // DNSTTCONFIGMODEL_H
