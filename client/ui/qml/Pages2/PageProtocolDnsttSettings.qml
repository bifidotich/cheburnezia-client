import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import PageEnum 1.0
import ProtocolEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"
import "../Components"

PageType {
    id: root

    // DNSTT is a client-side config: editing it only rewrites the stored
    // parameters, nothing is reconfigured on the server.
    property bool isEditingBlocked: ConnectionController.isConnected
                                    && ServersUiController.serverDefaultContainer(ServersUiController.defaultServerId)
                                       === ServersUiController.processedContainerIndex

    BackButtonType {
        id: backButton

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20 + PageController.safeAreaTopMargin

        onActiveFocusChanged: {
            if (backButton.enabled && backButton.activeFocus) {
                listView.positionViewAtBeginning()
            }
        }
    }

    QtObject {
        id: transportHint

        // Presentation-only classification of the first resolver. All
        // validation lives in DnsttConfigModel.
        readonly property string firstResolver: {
            var parts = DnsttConfigModel.resolvers.split(",")
            return parts.length > 0 ? parts[0].trim().toLowerCase() : ""
        }
        readonly property bool isDoh: firstResolver.indexOf("https://") === 0
        readonly property bool isDot: firstResolver.indexOf("dot://") === 0 || firstResolver.indexOf("tls://") === 0
        readonly property bool isPlainUdp: firstResolver.length > 0 && !isDoh && !isDot
    }

    Connections {
        target: InstallController

        function onUpdateContainerFinished(message, closePage) {
            PageController.showNotificationMessage(message)
            if (closePage) {
                PageController.closePage()
            }
        }
    }

    ListViewType {
        id: listView

        anchors.top: backButton.bottom
        anchors.bottom: saveButton.top
        anchors.right: parent.right
        anchors.left: parent.left

        header: ColumnLayout {
            width: listView.width
            spacing: 8

            BaseHeaderType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: 16

                headerText: qsTr("DNSTT settings")
                descriptionText: qsTr("DNS tunnel with Noise NK encryption and DoH/DoT transport")
            }
        }

        model: 1
        spacing: 16

        delegate: ColumnLayout {
            width: listView.width
            spacing: 16

            TextFieldWithHeaderType {
                id: domainField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("Tunnel domain") +
                            (DnsttConfigModel.domain.length > 0
                                 ? (" (MTU: " + DnsttConfigModel.calculatedMtu + qsTr(" bytes") + ")")
                                 : "")
                textField.placeholderText: "t.example.com"
                textField.text: DnsttConfigModel.domain
                textField.onTextChanged: DnsttConfigModel.domain = textField.text

                buttonText: qsTr("Paste")
                clickedFunc: function() {
                    // selectAll + paste replaces the selection. Clearing first
                    // would wipe the field when the clipboard is unavailable,
                    // which Android denies whenever the app is not in focus.
                    textField.selectAll()
                    textField.paste()
                    DnsttConfigModel.domain = textField.text
                }
            }

            WarningType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: DnsttConfigModel.domain.length > 0 && !DnsttConfigModel.isMtuValid
                textString: qsTr("Domain is too long! dnstt requires an MTU of at least 80 bytes (current MTU: %1 bytes)")
                        .arg(DnsttConfigModel.calculatedMtu)
            }

            TextFieldWithHeaderType {
                id: resolversField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("DNS Resolvers (comma separated)")
                textField.placeholderText: "https://8.8.8.8/dns-query"
                textField.text: DnsttConfigModel.resolvers
                textField.onTextChanged: DnsttConfigModel.resolvers = textField.text

                buttonText: qsTr("Paste")
                clickedFunc: function() {
                    // selectAll + paste replaces the selection. Clearing first
                    // would wipe the field when the clipboard is unavailable,
                    // which Android denies whenever the app is not in focus.
                    textField.selectAll()
                    textField.paste()
                    DnsttConfigModel.resolvers = textField.text
                }
            }

            WarningType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: !DnsttConfigModel.isResolversValid
                textString: DnsttConfigModel.resolversError
            }

            WarningType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: transportHint.isPlainUdp
                textString: qsTr("UDP mode transmits plain DNS packets and is vulnerable to DPI detection. Prefer DoH (https://) or DoT (dot://).")
            }

            TextFieldWithHeaderType {
                id: bootstrapField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: DnsttConfigModel.needsBootstrap
                enabled: !root.isEditingBlocked

                headerText: qsTr("Bootstrap DNS IP")
                textField.placeholderText: "1.1.1.1"
                textField.text: DnsttConfigModel.bootstrapIp
                textField.onTextChanged: DnsttConfigModel.bootstrapIp = textField.text
            }

            TextFieldWithHeaderType {
                id: keyField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("Server Public Key (64 hex characters)")
                textField.placeholderText: "0123456789abcdef..."
                textField.text: DnsttConfigModel.publicKey
                textField.onTextChanged: DnsttConfigModel.publicKey = textField.text

                buttonText: qsTr("Paste")
                clickedFunc: function() {
                    // selectAll + paste replaces the selection. Clearing first
                    // would wipe the field when the clipboard is unavailable,
                    // which Android denies whenever the app is not in focus.
                    textField.selectAll()
                    textField.paste()
                    DnsttConfigModel.publicKey = textField.text
                }
            }

            WarningType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: DnsttConfigModel.publicKey.length > 0 && !DnsttConfigModel.isPublicKeyValid
                textString: qsTr("The public key must be exactly 64 hexadecimal characters.")
            }

            WarningType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: root.isEditingBlocked
                textString: qsTr("Disconnect to change the connection parameters.")
            }

            CardType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                headerText: qsTr("Protocol specifics")
                bodyText: qsTr("• TCP-only: UDP traffic (QUIC, VoIP, games) is not carried; only DNS is relayed, over TCP.\n• VPS setup: dnstt-server must forward streams to a local SOCKS5 proxy.\n• Speed: typical throughput is 100-500 Kbps.")
            }

            LabelWithButtonType {
                id: removeButton

                Layout.fillWidth: true
                Layout.topMargin: 16

                text: qsTr("Remove ") + ContainersModel.getProcessedContainerName()
                textColor: AmneziaStyle.color.vibrantRed

                clickedFunction: function() {
                    var headerText = qsTr("Remove %1?").arg(ContainersModel.getProcessedContainerName())
                    var descriptionText = qsTr("The connection parameters will be deleted from this device.")
                    var yesButtonText = qsTr("Continue")
                    var noButtonText = qsTr("Cancel")

                    var yesButtonFunction = function() {
                        PageController.goToPage(PageEnum.PageDeinstalling)
                        InstallController.removeContainer(ServersUiController.processedServerId,
                                                          ServersUiController.processedContainerIndex)
                    }
                    var noButtonFunction = function() {}

                    showQuestionDrawer(headerText, descriptionText, yesButtonText, noButtonText,
                                       yesButtonFunction, noButtonFunction)
                }
            }

            DividerType {}
        }
    }

    BasicButtonType {
        id: saveButton

        anchors.right: root.right
        anchors.left: root.left
        anchors.bottom: root.bottom

        anchors.topMargin: 24
        anchors.bottomMargin: 24
        anchors.rightMargin: 16
        anchors.leftMargin: 16

        enabled: DnsttConfigModel.isValid && !root.isEditingBlocked

        text: qsTr("Save")

        onActiveFocusChanged: {
            if (activeFocus) {
                listView.positionViewAtEnd()
            }
        }

        clickedFunc: function() {
            var headerText = qsTr("Save settings?")
            var descriptionText = qsTr("Only the settings for this device will be changed")
            var yesButtonText = qsTr("Continue")
            var noButtonText = qsTr("Cancel")

            var yesButtonFunction = function() {
                if (root.isEditingBlocked) {
                    PageController.showNotificationMessage(qsTr("Unable change settings while there is an active connection"))
                    return
                }

                InstallController.updateClientConfig(ServersUiController.processedServerId,
                                                     ServersUiController.processedContainerIndex,
                                                     ProtocolEnum.Dnstt)
            }

            var noButtonFunction = function() {}

            showQuestionDrawer(headerText, descriptionText, yesButtonText, noButtonText,
                               yesButtonFunction, noButtonFunction)
        }
    }
}
