#ifndef OLCRTC_CONFIGURATOR_H
#define OLCRTC_CONFIGURATOR_H

#include <QObject>
#include <QJsonObject>

#include "configuratorBase.h"
#include "core/models/protocols/olcrtcProtocolConfig.h"

class OlcrtcConfigurator : public ConfiguratorBase
{
    Q_OBJECT
public:
    OlcrtcConfigurator(SshSession* sshSession, QObject *parent = nullptr);

    amnezia::ProtocolConfig createConfig(const amnezia::ServerCredentials &credentials,
                                         amnezia::DockerContainer container,
                                         const amnezia::ContainerConfig &containerConfig,
                                         const amnezia::DnsSettings &dnsSettings,
                                         amnezia::ErrorCode &errorCode) override;

    amnezia::ProtocolConfig processConfigWithLocalSettings(const amnezia::ConnectionSettings &settings,
                                                           amnezia::ProtocolConfig protocolConfig) override;
};

#endif // OLCRTC_CONFIGURATOR_H
