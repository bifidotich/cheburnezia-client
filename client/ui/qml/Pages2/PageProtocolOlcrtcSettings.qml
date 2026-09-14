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

    // olcRTC is a client-side config: editing it only rewrites the stored
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

                headerText: qsTr("olcRTC settings")
                descriptionText: qsTr("Encrypted tunnel disguised as a WebRTC video call")
            }
        }

        model: 1
        spacing: 16

        delegate: ColumnLayout {
            width: listView.width
            spacing: 16

            DropDownType {
                id: providerDropDown

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                descriptionText: qsTr("Provider")
                headerText: qsTr("Provider")

                drawerParent: root

                listView: ListViewWithRadioButtonType {
                    id: providerListView

                    rootWidth: root.width

                    model: ListModel {
                        ListElement { name: "jitsi" }
                        ListElement { name: "telemost" }
                        ListElement { name: "wbstream" }
                        ListElement { name: "none" }
                    }

                    function updateSelectedIndex() {
                        providerDropDown.text = OlcrtcConfigModel.provider
                        for (var i = 0; i < providerListView.model.count; i++) {
                            if (providerListView.model.get(i).name === OlcrtcConfigModel.provider) {
                                selectedIndex = i
                                break
                            }
                        }
                    }

                    clickedFunction: function() {
                        providerDropDown.text = selectedText
                        OlcrtcConfigModel.provider = selectedText
                        providerDropDown.closeTriggered()
                    }

                    Component.onCompleted: updateSelectedIndex()
                }
            }

            DropDownType {
                id: transportDropDown

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                descriptionText: qsTr("Transport")
                headerText: qsTr("Transport")

                drawerParent: root

                listView: ListViewWithRadioButtonType {
                    id: transportListView

                    rootWidth: root.width

                    model: ListModel {
                        ListElement { name: "datachannel" }
                        ListElement { name: "vp8channel" }
                        ListElement { name: "seichannel" }
                        ListElement { name: "videochannel" }
                    }

                    function updateSelectedIndex() {
                        transportDropDown.text = OlcrtcConfigModel.transport
                        for (var i = 0; i < transportListView.model.count; i++) {
                            if (transportListView.model.get(i).name === OlcrtcConfigModel.transport) {
                                selectedIndex = i
                                break
                            }
                        }
                    }

                    clickedFunction: function() {
                        transportDropDown.text = selectedText
                        OlcrtcConfigModel.transport = selectedText
                        transportDropDown.closeTriggered()
                    }

                    Component.onCompleted: updateSelectedIndex()
                }
            }

            TextFieldWithHeaderType {
                id: roomField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("Room URL")
                textField.placeholderText: "https://meet.example.com/room"
                textField.text: OlcrtcConfigModel.roomUrl
                textField.onTextChanged: OlcrtcConfigModel.roomUrl = textField.text

                buttonText: qsTr("Paste")
                clickedFunc: function() {
                    textField.selectAll()
                    textField.paste()
                    OlcrtcConfigModel.roomUrl = textField.text
                }
            }

            TextFieldWithHeaderType {
                id: keyField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("Shared key (64 hex characters)")
                textField.placeholderText: "0123456789abcdef..."
                textField.text: OlcrtcConfigModel.key
                textField.onTextChanged: OlcrtcConfigModel.key = textField.text

                buttonText: qsTr("Paste")
                clickedFunc: function() {
                    textField.selectAll()
                    textField.paste()
                    OlcrtcConfigModel.key = textField.text
                }
            }

            WarningType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                visible: OlcrtcConfigModel.key.length > 0 && !OlcrtcConfigModel.isKeyValid
                textString: qsTr("The key must be exactly 64 hexadecimal characters.")
            }

            TextFieldWithHeaderType {
                id: dnsField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("DNS resolver (optional)")
                textField.placeholderText: "1.1.1.1"
                textField.text: OlcrtcConfigModel.dns
                textField.onTextChanged: OlcrtcConfigModel.dns = textField.text
            }

            TextFieldWithHeaderType {
                id: tokenField

                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16

                enabled: !root.isEditingBlocked

                headerText: qsTr("Provider token (optional)")
                textField.text: OlcrtcConfigModel.providerToken
                textField.onTextChanged: OlcrtcConfigModel.providerToken = textField.text
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
                bodyText: qsTr("• Traffic is disguised as a video call on the chosen provider.\n• TCP-only: UDP traffic (QUIC, VoIP, games) is not carried; only DNS is relayed, over TCP.\n• Setup: an olcRTC server peer and a room on the provider are required.")
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

        enabled: OlcrtcConfigModel.isValid && !root.isEditingBlocked

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
                                                     ProtocolEnum.Olcrtc)
            }

            var noButtonFunction = function() {}

            showQuestionDrawer(headerText, descriptionText, yesButtonText, noButtonText,
                               yesButtonFunction, noButtonFunction)
        }
    }
}
