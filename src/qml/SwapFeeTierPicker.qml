import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "kit/fees.js" as Fees

// Low / Market / Fast, as radio buttons. The values are fee_module's own: slow, normal, fast.
// The Ethereum wallet's EthFeeTierPicker (logos-eth-wallet-ui), with what each tier pays per gas
// under its name when fee_module said. kit/ stays exactly the kit at its pin (its FeeTierPicker
// offers three buttons), so the radio form lives here until the kit takes it.
ColumnLayout {
    id: picker
    property string tier: "normal"
    // tier -> a short line under its name ("up to 1.7 gwei"); "" or missing shows none.
    property var estimates: ({})

    spacing: Theme.spacing.tiny

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.medium
        // A choice of one, so radio buttons, not three buttons that read as actions. checked is
        // driven by `tier` (checkable off, as the wallet does) so a click can't break the binding.
        Repeater {
            model: [["slow", "tierSlow"], ["normal", "tierNormal"], ["fast", "tierFast"]]
            ColumnLayout {
                required property var modelData
                spacing: 0
                // The ring in the tertiary border over the page's background: the design system's
                // default (border over surface) all but vanishes on the framed Fee card.
                LogosRadioButton {
                    objectName: modelData[1]
                    borderColor: Theme.palette.borderTertiary !== undefined ? Theme.palette.borderTertiary : Theme.palette.textTertiary
                    boxColor: Theme.palette.background
                    text: Fees.tierName(modelData[0])
                    checkable: false
                    checked: picker.tier === modelData[0]
                    onClicked: picker.tier = modelData[0]
                }
                LogosText {
                    objectName: modelData[1] + "Estimate"
                    readonly property string line: picker.estimates && picker.estimates[modelData[0]]
                                                   ? String(picker.estimates[modelData[0]]) : ""
                    visible: line.length > 0
                    Layout.leftMargin: 28
                    textFormat: Text.PlainText
                    text: line
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
            }
        }
        Item { Layout.fillWidth: true }
    }
}
