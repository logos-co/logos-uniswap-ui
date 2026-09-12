// Asking other apps for things, LOADED and DRIVEN, with no app, no backend and no shell.
//
// Three of this view's controls name a CAPABILITY rather than an app, and the shell resolves
// it. What matters is which intent goes out, what travels with it, and that each answer
// lands somewhere sensible — including "nobody can do this", which has to leave the user
// with an instruction.
import QtQuick

Item {
    id: probe
    width: 900
    height: 700

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string handle: "ksh_7f3c9a"
    readonly property string oldSignerText: "Approve this swap in the Signer app to send it."

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
    // A LogosDialog is a Popup: its contentItem is not in the tree `find` walks. And never
    // assert a popup's `visible` here — with no window it reads false whatever its binding
    // says. What the view decides is asserted instead.
    function inDialog(dialogName, name) {
        var d = find(view.item, dialogName)
        var hit = (d && d.contentItem) ? find(d.contentItem, name) : null
        return hit || ({ text: "<missing>", visible: "<missing>" })
    }
    function press(name) {
        var b = find(view.item, name)
        if (!b) { probe.failures++; console.log("  FAIL  " + name + " is not in the tree"); return false }
        b.clicked()
        return true
    }

    property var requests: []
    property var reply: null
    function lastRequest() { return probe.requests.length ? probe.requests[probe.requests.length - 1] : ({ intent: "<none>", params: {} }) }
    function answer(res) { var cb = probe.reply; probe.reply = null; if (cb) cb(res) }
    property int cancels: 0

    property var logos: ({
        module: function (n) { return fake }, isViewModuleReady: function (n) { return true },
        request: function (intent, params, cb) {
            var r = probe.requests; r.push({ intent: intent, params: params }); probe.requests = r; probe.reply = cb
        }
    })

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
        property string accountsJson: JSON.stringify([probe.me])
        property string selectedAccount: probe.me
        property string accountLabelsJson: "{}"
        property string accountWalletsJson: "{}"
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
        function selectAccount(a) {}
        function searchTokens(q) {}
        function quote(r) {}
        function setQuoteAutoRefresh(on) {}
        function setSettings(j) {}
        function submitSwap(r) {}
        function pollSwap() {}
        function cancelSwap() { probe.cancels++; fake.pendingRequestId = ""; fake.pendingApprovalHandle = "" }
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
            var v = view.item
            console.log("a swap waiting on a human. The handle arriving is what asks — nobody clicks")
            fake.pendingRequestId = "snd_1"
            fake.pendingApprovalHandle = probe.handle
            check("the signing intent went out", probe.lastRequest().intent, "evm.signing.approve")
            check("...carrying the KEYSTORE's handle, not our request id", probe.lastRequest().params.handle, probe.handle)
            check("the waiting dialog says so", probe.inDialog("pendingDialog", "pendingLabel").text, "Waiting for this swap to be approved.")

            console.log("")
            console.log("the answers. Success and a refusal by the human say nothing here")
            probe.answer({ ok: true })
            check("success writes no note", v.approvalNote, "")
            fake.pendingApprovalHandle = ""; fake.pendingApprovalHandle = probe.handle
            probe.answer({ ok: false, error: "unavailable" })
            check("unavailable puts the manual instruction back", v.approvalNote, probe.oldSignerText)
            check("...and does NOT withdraw the record", probe.cancels, 0)
            check("...the dialog now carries it", probe.inDialog("pendingDialog", "pendingLabel").text, probe.oldSignerText)
            fake.pendingApprovalHandle = ""; fake.pendingApprovalHandle = probe.handle
            probe.answer({ ok: false, error: "cancelled" })
            check("cancelled: the user declined to route it, so the record is withdrawn", probe.cancels, 1)
            fake.pendingRequestId = "snd_2"; fake.pendingApprovalHandle = probe.handle
            probe.answer({ ok: false, error: "timeout" })
            check("timeout: the path is closed, the record is withdrawn", probe.cancels, 2)
            check("...and the note says what happened", v.approvalNote, "Could not reach a signer (timeout).")
            fake.pendingRequestId = "snd_3"; fake.pendingApprovalHandle = probe.handle
            probe.answer({ ok: false, error: "bad_request" })
            check("bad_request too", probe.cancels, 3)

            console.log("")
            console.log("the hand-offs: Accounts and Token lists name a capability, and nobody may hold it")
            press("manageAccountsButton")
            check("Accounts asks for the accounts intent", probe.lastRequest().intent, "evm.accounts.manage")
            probe.answer({ ok: false, error: "unavailable" })
            check("...and says so when nobody offers it", v.intentNote, "No app on this device manages accounts.")
            v.selectTab(2)
            press("tokenListsEntry")
            check("Token lists asks for the token-lists intent", probe.lastRequest().intent, "evm.token_lists.configure")
            probe.answer({ ok: false, error: "unavailable" })
            check("...with its own instruction", v.intentNote, "No app on this device manages token lists.")
            probe.answer({ ok: true })
            press("tokenListsEntry")
            probe.answer({ ok: true })
            check("a hand-off that went through leaves no note", v.intentNote, "")

            console.log("")
            console.log("the outcome dialog, when the swap settles")
            fake.pendingRequestId = ""
            fake.lastSwapOutcomeJson = JSON.stringify({ status: "broadcast", hashes: ["0xa0", "0xa1"] })
            check("it is shown", v.showOutcome, true)
            check("...counting the transactions", probe.inDialog("swapOutcomeDialog", "swapOutcomeLabel").text, "Sent to the network: 2 transactions.")
            v.dismissOutcome()
            check("dismissed, it stays down", v.showOutcome, false)
            fake.lastSwapOutcomeJson = JSON.stringify({ status: "rejected" })
            check("a rejection is a new outcome", probe.inDialog("swapOutcomeDialog", "swapOutcomeLabel").text, "The signer rejected this swap.")
            fake.lastSwapOutcomeJson = JSON.stringify({ status: "stuck", reason: "the broadcast has not answered" })
            check("stuck says the swap may be on chain", String(probe.inDialog("swapOutcomeDialog", "swapOutcomeLabel").text).indexOf("may still be on chain") > 0, true)

            console.log("")
            console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
            Qt.exit(probe.failures ? 1 : 0)
        }
    }
}
