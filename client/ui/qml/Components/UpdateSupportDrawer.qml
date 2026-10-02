import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import Style 1.0

import "../Controls2"
import "../Controls2/TextTypes"
import "../Config"

DrawerType2 {
    id: root

    expandedStateContent: Item {
        id: contentRoot

        implicitHeight: content.implicitHeight + 40 + PageController.safeAreaBottomMargin

        Binding {
            target: root
            property: "expandedHeight"
            value: contentRoot.implicitHeight
        }

        ColumnLayout {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 24
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 0

            Header2TextType {
                Layout.fillWidth: true

                text: qsTr("Support")
            }

            AppTextType {
                Layout.fillWidth: true
                Layout.topMargin: 8

                color: AmneziaStyle.color.textTertiary
                text: qsTr("If the update won't install, message us")
            }

            // Fork: the GitHub releases page replaces Amnezia's Telegram, email and
            // website. The repository URL is the About page's, which
            // branding/translations/overrides.json points at the fork.
            LabelWithButtonType {
                Layout.fillWidth: true
                Layout.topMargin: 16

                text: qsTranslate("PageSettingsAbout", "GitHub")
                descriptionText: qsTr("Download the update manually")
                leftImageSource: "qrc:/images/controls/github.svg"
                rightImageSource: "qrc:/images/controls/chevron-right.svg"

                clickedFunction: function() {
                    Qt.openUrlExternally(qsTranslate("PageSettingsAbout", "https://github.com/amnezia-vpn/amnezia-client") + "/releases")
                }
            }
        }
    }
}
