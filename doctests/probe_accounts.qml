// The account picker over the signer manager's roster: each account once, with every signer
// holding it, and a word when only devices that take one transaction at a time hold it.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string mine: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string shell: "0x9858EfFD232B4033E47d90003D41EC34EcaEda94"
    readonly property string later: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

    property int failures: 0
    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok) probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got + (ok ? "" : "  want=" + want))
    }
    function find(o, name) {
        if (!o) return null
        if (o.objectName === name) return o
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i) { var hit = find(kids[i], name); if (hit) return hit }
        return null
    }
    function node(name) { return find(view.item, name) || ({ text: "<missing>", visible: "<missing>" }) }

    property var selections: []
    property var logos: ({
        module: function (n) { return fake }, isViewModuleReady: function (n) { return true },
        request: function (intent, params, cb) {}
    })

    readonly property var roster: [
        { key: mine.toLowerCase(), family: "evm", address: mine, path: "m/44'/60'/0'/0/0", label: "Savings",
          wallet: { fingerprint: "73c5da0a", name: "Main" },
          holders: [{ signer: "keystore_module", transport: "keystore", presence: "local", kind: "keystore", requestKinds: ["hash"] }] },
        { key: shell.toLowerCase(), family: "evm", address: shell, path: "m/44'/60'/0'/0/0", label: "Travel",
          wallet: { fingerprint: "9a3c11f0" },
          holders: [{ signer: "keycard_shell_module", transport: "usb", presence: "connected", kind: "keycard_shell",
                      requestKinds: ["evm_transaction", "evm_message"] }] }
    ]

    QtObject {
        id: fake
        property string lastError: ""
        property string swapError: ""
        property bool scopedDataFresh: true
        property bool dataLoading: false
        property bool quoteLoading: false
        property bool catalogueLoading: false
        property bool feeTiersLoading: false
        property bool swapPolling: false
        property string activeNetworkJson: JSON.stringify({ chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true })
        property string networksJson: "[]"
        property string verifiedProxyJson: JSON.stringify({ ok: true, chainId: 11155111, mode: "off" })
        property string accountsJson: JSON.stringify([probe.mine, probe.shell, probe.later])
        property string selectedAccount: probe.mine
        property string accountLabelsJson: JSON.stringify({ "70997970c51812dc3a010c7d01b50e0d17dc79c8": "Spare" })
        property string accountWalletsJson: "{}"
        property string accountRosterJson: JSON.stringify(probe.roster)
        property string tokensJson: "[]"
        property string balancesJson: "[]"
        property string balancesRoute: "direct"
        property string catalogueJson: ""
        property string feeTiersJson: "{}"
        property string quoteJson: "{}"
        property string quoteRequestJson: ""
        property bool quoteStale: false
        property string settingsJson: JSON.stringify({ slippageBps: 50, autoSlippage: true, deadlineMins: 30 })
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSwapOutcomeJson: ""
        property string swapsJson: "[]"
        property bool sweepingReceipts: false
        function refresh() {}
        function selectAccount(a) { probe.selections = probe.selections.concat([a]); fake.selectedAccount = a }
        function searchTokens(q) {}
        function loadMoreCatalogue() {}
        function quote(r) {}
        function setQuoteAutoRefresh(on) {}
        function setSettings(j) {}
        function submitSwap(r) {}
        function pollSwap() {}
        function cancelSwap() {}
        function refreshSwaps() {}
        function refreshPending() {}
    }

    Loader {
        id: view
        anchors.fill: parent
        onStatusChanged: {
            if (status === Loader.Error) { console.log("  FAIL  the view did not load"); Qt.exit(1) }
            if (status !== Loader.Ready) return
            item.ready = true
            settle.start()
        }
    }
    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/UniswapView.qml")

    Timer {
        id: settle
        interval: 200
        onTriggered: {
            var picker = probe.node("accountPicker")
            console.log("")
            console.log("one row per account, and in this header the account alone")
            check("three rows", picker.model.length, 3)
            check("the selected account by name", probe.node("accountPickerSelectedName").text, "Savings")
            check("...and address", probe.node("accountPickerSelectedAddress").text, "0x8626…1199")
            check("no wallet line in the header", probe.node("accountPickerSelectedWallet").visible, false)
            check("the keystore signs a swap with an approval: no note", probe.node("accountBundleNote").visible, false)

            console.log("")
            console.log("an account only a Shell holds: it takes one transaction at a time")
            picker.activated(1)
            check("the backend is told the address", JSON.stringify(probe.selections), JSON.stringify([probe.shell]))
            check("...and the picker follows", picker.currentIndex, 1)
            check("the note says so", probe.node("accountBundleNote").visible, true)

            console.log("")
            console.log("an account the roster hasn't listed yet shows by its own name, and nothing against it")
            fake.selectedAccount = probe.later
            check("by name", probe.node("accountPickerSelectedName").text, "Spare")
            check("no note", probe.node("accountBundleNote").visible, false)

            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }
}
