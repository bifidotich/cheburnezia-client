#include "olcrtcConfigurator.h"
#include "core/protocols/protocolUtils.h"
#include "core/utils/constants/configKeys.h"

using namespace amnezia;

OlcrtcConfigurator::OlcrtcConfigurator(SshSession* sshSession, QObject *parent)
    : ConfiguratorBase(sshSession, parent)
{
}

ProtocolConfig OlcrtcConfigurator::createConfig(const ServerCredentials &credentials,
                                                DockerContainer container,
                                                const ContainerConfig &containerConfig,
                                                const DnsSettings &dnsSettings,
                                                ErrorCode &errorCode)
{
    Q_UNUSED(credentials)
    Q_UNUSED(container)
    Q_UNUSED(dnsSettings)
    errorCode = ErrorCode::NoError;
    return containerConfig.protocolConfig;
}

ProtocolConfig OlcrtcConfigurator::processConfigWithLocalSettings(const ConnectionSettings &settings,
                                                                  ProtocolConfig protocolConfig)
{
    applyDnsToNativeConfig(settings.dns, protocolConfig);
    return protocolConfig;
}
