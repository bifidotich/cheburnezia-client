import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import PageEnum 1.0
import Style 1.0

import "./"
import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"

PageType {
    id: root

    BackButtonType {
        id: backButton

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20 + PageController.safeAreaTopMargin

        onFocusChanged: {
            if (this.activeFocus) {
                listView.positionViewAtBeginning()
            }
        }
    }

    ListViewType {
        id: listView

        anchors.top: backButton.bottom
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: parent.left

        header: ColumnLayout {
            width: listView.width
            spacing: 8

            BaseHeaderType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                headerText: qsTr("olcRTC Connection")
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
                headerText: qsTr("Room URL")
                textField.placeholderText: "https://meet.example.com/room"
                textField.text: OlcrtcConfigModel.roomUrl
                textField.onTextChanged: OlcrtcConfigModel.roomUrl = textField.text
            }

            TextFieldWithHeaderType {
                id: keyField
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
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
                headerText: qsTr("DNS resolver (optional)")
                textField.placeholderText: "1.1.1.1"
                textField.text: OlcrtcConfigModel.dns
                textField.onTextChanged: OlcrtcConfigModel.dns = textField.text
            }

            CardType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                headerText: qsTr("Protocol specifics")
                bodyText: qsTr("• Traffic is disguised as a video call on the chosen provider.\n• TCP-only: UDP traffic (QUIC, VoIP, games) is not carried; only DNS is relayed, over TCP.\n• Setup: an olcRTC server peer and a room on the provider are required.")
            }
        }

        footer: ColumnLayout {
            width: listView.width
            Layout.topMargin: 16
            Layout.bottomMargin: 32

            BasicButtonType {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                text: qsTr("Continue")
                enabled: OlcrtcConfigModel.isValid

                clickedFunc: function() {
                    if (ImportController.extractConfigFromData(OlcrtcConfigModel.generateUri())) {
                        PageController.goToPage(PageEnum.PageSetupWizardViewConfig)
                    }
                }
            }
        }
    }
}
