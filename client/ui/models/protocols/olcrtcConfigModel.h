#ifndef OLCRTCCONFIGMODEL_H
#define OLCRTCCONFIGMODEL_H

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QStringList>

#include "core/utils/containerEnum.h"
#include "core/models/protocols/olcrtcProtocolConfig.h"

class OlcrtcConfigModel : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString provider READ provider WRITE setProvider NOTIFY providerChanged)
    Q_PROPERTY(QString transport READ transport WRITE setTransport NOTIFY transportChanged)
    Q_PROPERTY(QString roomUrl READ roomUrl WRITE setRoomUrl NOTIFY roomUrlChanged)
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(QString dns READ dns WRITE setDns NOTIFY dnsChanged)
    Q_PROPERTY(QString providerToken READ providerToken WRITE setProviderToken NOTIFY providerTokenChanged)
    Q_PROPERTY(QStringList providers READ providers CONSTANT)
    Q_PROPERTY(QStringList transports READ transports CONSTANT)
    Q_PROPERTY(bool isKeyValid READ isKeyValid NOTIFY isKeyValidChanged)
    Q_PROPERTY(bool isValid READ isValid NOTIFY isValidChanged)

public:
    explicit OlcrtcConfigModel(QObject *parent = nullptr);

    QString provider() const;
    void setProvider(const QString &provider);

    QString transport() const;
    void setTransport(const QString &transport);

    QString roomUrl() const;
    void setRoomUrl(const QString &roomUrl);

    QString key() const;
    void setKey(const QString &key);

    QString dns() const;
    void setDns(const QString &dns);

    QString providerToken() const;
    void setProviderToken(const QString &providerToken);

    QStringList providers() const;
    QStringList transports() const;

    bool isKeyValid() const;
    bool isValid() const;

    Q_INVOKABLE QString getValidationError() const;
    Q_INVOKABLE QString generateUri() const;

public slots:
    // Loads the stored container config so the settings page shows the values
    // the tunnel is actually running with. The container argument is unused,
    // but keeps the signature uniform with the other protocol config models so
    // InstallUiController can drive them all the same way.
    void updateModel(amnezia::DockerContainer container, const amnezia::OlcrtcProtocolConfig &protocolConfig);
    void updateModel(const QJsonObject &config);

    amnezia::OlcrtcProtocolConfig getProtocolConfig() const;
    QJsonObject getConfig() const;

signals:
    void providerChanged();
    void transportChanged();
    void roomUrlChanged();
    void keyChanged();
    void dnsChanged();
    void providerTokenChanged();
    void isKeyValidChanged();
    void isValidChanged();

private:
    amnezia::OlcrtcProtocolConfig m_config;
};

#endif // OLCRTCCONFIGMODEL_H
