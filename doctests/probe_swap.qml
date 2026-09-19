// The Swap page, LOADED and DRIVEN, with no app and no backend.
//
// The C++ tables beside this run every rule that is a pure function over a reply. What they
// cannot reach is what the BUTTON says for a given form and quote, and what the cards and the
// rows render — bindings, which only evaluating them can check. So this stands the view up
// under an offscreen Qt with a fabricated backend and asserts what it SAYS.
//
// The fake backend is a QtObject: a write to its properties notifies, and half of this file
// MOVES a published property and watches the view react.
import QtQuick

Item {
    id: probe
    width: 1000
    height: 900

    readonly property string me: "0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199"
    readonly property string usdc: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
    readonly property string weth: "0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
    readonly property string router: "0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E"

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
        for (var i = 0; i < kids.length; ++i) {
            var hit = find(kids[i], name)
            if (hit) return hit
        }
        return null
    }
    function node(name) {
        return find(view.item, name) || ({ text: "<missing>", visible: "<missing>", enabled: "<missing>", value: "<missing>" })
    }
    function inDialog(dialogName, name) {
        var d = find(view.item, dialogName)
        var hit = (d && d.contentItem) ? find(d.contentItem, name) : null
        return hit || ({ text: "<missing>", visible: "<missing>", value: "<missing>" })
    }

    readonly property var ethToken: ({ symbol: "ETH", name: "Ether", decimals: 18, native: true })
    readonly property var usdcToken: ({ symbol: "USDC", name: "USD Coin", decimals: 6, address: probe.usdc, source: "allowlist" })

    property var requests: []
    property var logos: ({
        module: function (n) { return fake }, isViewModuleReady: function (n) { return true },
        request: function (intent, params, cb) { var r = probe.requests; r.push({ intent: intent, params: params }); probe.requests = r }
    })

    // What the backend's quote pipeline was asked, so the request the form describes can be
    // asserted rather than inferred.
    property var quoted: []

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
        property string tokensJson: JSON.stringify([probe.ethToken, probe.usdcToken])
        property string balancesJson: JSON.stringify([
            { symbol: "ETH", native: true, display: "1.5", exact: "1.5" },
            { symbol: "USDC", address: probe.usdc, display: "2500", exact: "2500" }])
        property string balancesRoute: "direct"
        property string catalogueJson: ""
        property string feeTiersJson: JSON.stringify({ source: "eip1559" })
        property string quoteJson: "{}"
        property string quoteRequestJson: ""
        property bool quoteStale: false
        property string settingsJson: JSON.stringify({ slippageBps: 50, autoSlippage: true, deadlineMins: 30 })
        property string pendingRequestId: ""
        property string pendingApprovalHandle: ""
        property string lastSwapOutcomeJson: ""
        property string swapsJson: JSON.stringify([{
            requestId: "snd_1", status: "confirmed", timestamp: 1756600000, origin: "uniswap_backend", via: "uniswap_ui",
            hashes: ["0xa0", "0xa1"], label: "Swap USDC for ETH on Uniswap V3",
            swap: { kind: "swap", symbolIn: "USDC", symbolOut: "ETH", amountIn: "1000000000", decimalsIn: 6,
                    amountOut: "333277787035494084", decimalsOut: 18, amountOutMin: "331611398100316613",
                    route: { version: "V3", viaWeth: false, hops: [{ fee: 500 }] } },
            legs: [{ hash: "0xa0", leg: 0, status: "confirmed", label: "Approve USDC for Uniswap", to: probe.usdc },
                   { hash: "0xa1", leg: 1, status: "confirmed", label: "Swap USDC for ETH on Uniswap V3", to: probe.router }]
        }])
        property bool sweepingReceipts: false
        function refresh() {}
        function selectAccount(a) {}
        function selectNetwork(chainId) {}
        function searchTokens(q) {}
        function loadMoreCatalogue() {}
        function quote(r) { var l = probe.quoted; l.push(r); probe.quoted = l }
        function setQuoteAutoRefresh(on) {}
        function setSettings(j) {}
        function submitSwap(r) {}
        function pollSwap() {}
        function cancelSwap() {}
        function refreshSwaps() {}
        function refreshPending() {}
    }

    // A quote the backend would publish for 1000 USDC -> ETH, paired with the request the
    // form describes RIGHT NOW.
    function publishQuote(extra) {
        var r = probe.quoted[probe.quoted.length - 1]
        var q = {
            ok: true, chainId: 11155111, owner: probe.me, from: probe.me,
            amountIn: "1000000000", amountOut: "333277787035494084", amountOutMin: "331611398100316613",
            amountInDisplay: "1000", amountOutDisplay: "0.33327", amountOutExact: "0.333277787035494084",
            amountOutMinDisplay: "0.33161", rate: "0.000333278", rateInverse: "3000.5",
            route: { version: "V3", viaWeth: false, hops: [{ tokenIn: probe.usdc, tokenOut: probe.weth, fee: 500 }] },
            feeBps: 5, priceImpactBps: 2, gasLimitHint: 235000, spender: probe.router,
            balanceIn: "2500000000", balanceInDisplay: "2500", insufficientBalance: false,
            needsApproval: true, approval: "set",
            calls: [{ kind: "approve", to: probe.usdc, label: "Approve USDC for Uniswap" },
                    { kind: "swap", to: probe.router, label: "Swap USDC for ETH on Uniswap V3" }],
            fee: { ok: true, feeCeilingWeiDisplay: "0.0004", nativeSymbol: "ETH", feeSource: "eip1559", nonce: 7 }
        }
        for (var k in extra) q[k] = extra[k]
        fake.quoteJson = JSON.stringify(q)
        fake.quoteRequestJson = r
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
        interval: 300
        onTriggered: {
            var v = view.item
            console.log("the network picker follows the backend's two-step publication")
            var picker = probe.node("chainPicker")
            fake.networksJson = JSON.stringify([
                { chainId: 1, name: "Ethereum", nativeSymbol: "ETH", testnet: false }
            ])
            check("the choices alone cannot select a different active chain", picker.currentIndex, -1)
            fake.activeNetworkJson = JSON.stringify(
                { chainId: 1, name: "Ethereum", nativeSymbol: "ETH", testnet: false })
            check("publishing the chosen chain selects its row", picker.currentIndex, 0)
            fake.networksJson = JSON.stringify([
                { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true }
            ])
            fake.activeNetworkJson = JSON.stringify(
                { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true })
            check("and a later chain publication stays synchronized", picker.currentIndex, 0)

            console.log("")
            console.log("a blocking verdict says what to do, for every action eth_rpc sends")
            var actions = ["wait", "install_or_load", "open_verified_proxy", "restart_or_reload"]
            for (var ai = 0; ai < actions.length; ++ai) {
                fake.verifiedProxyJson = JSON.stringify({ ok: true, chainId: 11155111, mode: "required",
                                                          blocking: true, action: actions[ai], message: "blocked" })
                check(actions[ai] + " has a hint", probe.node("verifiedBannerAction").text !== "", true)
            }
            fake.verifiedProxyJson = JSON.stringify({ ok: true, chainId: 11155111, mode: "off" })
            check("...and the banner goes when the verdict stops blocking", probe.node("verifiedBanner").visible, false)

            console.log("")
            console.log("the button says what is missing, in Uniswap's own order")
            var page = probe.find(v, "swapPage")
            check("the network coin is seeded as the sell side", page.sellSymbol, "ETH")
            check("nothing to buy yet: the button asks for a token", probe.node("swapButton").text, "Select a token")
            check("...and is disabled", probe.node("swapButton").enabled, false)
            page.selectToken("buy", probe.usdcToken)
            check("a pair with no amount asks for one", probe.node("swapButton").text, "Enter an amount")
            page.selectToken("buy", probe.ethToken)
            check("the same token twice is refused", probe.node("swapButton").text, "Choose two different tokens")

            console.log("")
            console.log("1000 USDC for ETH: the form describes a request and the backend prices it")
            page.selectToken("sell", probe.usdcToken)
            page.selectToken("buy", probe.ethToken)
            var sellField = probe.node("sellAmountField")
            sellField.text = "1000"
            fake.quoteLoading = true
            check("the button says it is pricing", probe.node("swapButton").text, "Pricing…")
            var req = JSON.parse(probe.quoted[probe.quoted.length - 1])
            check("the request names the account", req.from, probe.me)
            check("...the input as its contract", req.tokenIn, probe.usdc)
            check("...ether as ETH", req.tokenOut, "ETH")
            check("...the amount in token units, untouched", req.amountUnits, "1000")
            check("...the input's decimals", req.decimalsIn, 6)
            check("...the default slippage", req.slippageBps, 50)
            check("...and the default deadline", req.deadlineMins, 30)
            fake.quoteLoading = false
            probe.publishQuote({})
            check("the buy card shows the quoted output", probe.node("buyAmountLabel").text, "0.33327")
            check("the rate line", probe.node("rateLine").text, "1 USDC = 0.000333278 ETH")
            check("the minimum received", probe.node("minReceivedRow").value, "0.33161 ETH")
            check("the price impact, as a percentage", probe.node("impactRow").value, "0.02%")
            check("the route", probe.node("routeRow").value, "Uniswap V3 0.05%")
            check("the pool fee", probe.node("feeTierRow").value, "0.05%")
            check("the approval, said before it is asked", probe.node("approvalRow").value, "Approve USDC first")
            check("the fee is a ceiling, never a price", probe.node("feeRow").value, "at most 0.0004 ETH (normal)")
            check("and the button offers the swap on the named network", probe.node("swapButton").text, "Swap on Sepolia (testnet)")
            check("...enabled", probe.node("swapButton").enabled, true)

            console.log("")
            console.log("the figures are withdrawn the moment the form changes")
            sellField.text = "1001"
            check("a changed amount unpairs the quote", probe.node("buyAmountLabel").text, "0")
            check("...and the button no longer offers it", probe.node("swapButton").enabled, false)
            sellField.text = "1000"
            check("the same request pairs again", probe.node("buyAmountLabel").text, "0.33327")

            console.log("")
            console.log("what the quote can say against the swap")
            probe.publishQuote({ insufficientBalance: true })
            check("a balance short of the amount", probe.node("swapButton").text, "Insufficient USDC balance")
            probe.publishQuote({ fee: { ok: false, error: "the account cannot afford this: 0.001 ETH short" } })
            check("a fee the account cannot pay", probe.node("swapButton").text, "Not enough ETH for gas")
            check("...with the sender's words on screen", probe.node("feeErrorLabel").text, "Fee: the account cannot afford this: 0.001 ETH short")
            probe.publishQuote({ priceImpactBps: 350 })
            check("3.5% impact is a warning colour, not a gate", probe.node("swapButton").text, "Swap on Sepolia (testnet)")
            probe.publishQuote({ priceImpactBps: 800 })
            check("8% impact needs an acknowledgement", probe.node("swapButton").text, "Swap anyway")
            check("...and the button waits for it", probe.node("swapButton").enabled, false)
            check("...beside a warning that says the figure", probe.node("impactWarning").visible, true)
            page.impactAcknowledged = true
            check("acknowledged, the swap is offered", probe.node("swapButton").enabled, true)
            sellField.text = "999"
            check("...and a changed form asks again", page.impactAcknowledged, false)
            sellField.text = "1000"
            fake.quoteJson = "{}"; fake.quoteRequestJson = ""
            fake.swapError = "no route found"
            check("no route, in the module's words", probe.node("swapButton").text, "No route")
            check("...and the reason is on screen", probe.node("swapErrorLabel").text, "no route found")
            fake.swapError = "no answer within 8699ms: operation timed out"
            check("any other refusal says the quote failed, not that a swap is on offer", probe.node("swapButton").text, "Could not quote")
            fake.swapError = ""
            probe.publishQuote({ fee: { ok: false, error: "the node did not answer" } })
            check("a fee that could not be priced for another reason says so", probe.node("swapButton").text, "Fee unavailable")
            probe.publishQuote({})
            fake.pendingRequestId = "snd_9"
            check("a swap awaiting a human holds the button", probe.node("swapButton").text, "Waiting for approval")
            fake.pendingRequestId = ""

            console.log("")
            console.log("the review dialog lists every transaction the signer will be asked for")
            var review = probe.find(v, "reviewDialog")
            check("you pay", probe.inDialog("reviewDialog", "reviewPay").value, "1000 USDC")
            check("you receive", probe.inDialog("reviewDialog", "reviewReceive").value, "0.33327 ETH")
            check("at least", probe.inDialog("reviewDialog", "reviewMin").value, "0.33161 ETH")
            check("the first transaction is the approval", probe.inDialog("reviewDialog", "reviewCall_0").text, "1. Approve USDC for Uniswap · 0x1c7D…7238")
            check("the second is the swap", probe.inDialog("reviewDialog", "reviewCall_1").text, "2. Swap USDC for ETH on Uniswap V3 · 0x3bFA…e48E")

            console.log("")
            console.log("the Activity tab shows this app's bundles, one row per swap")
            v.selectTab(1)
            activitySettle.start()
        }
    }
    Timer {
        id: activitySettle
        interval: 300
        onTriggered: {
            var v = view.item
            check("one row for the two-transaction swap", probe.node("swapTitle_snd_1").text, "Swap 1000 USDC for 0.33327 ETH")
            check("...settled as a whole", probe.node("swapStatus_snd_1").text, "confirmed")
            check("...counting its transactions", String(probe.node("swapWhen_snd_1").text).indexOf("2 transactions") > 0, true)
            v.openSwapDetail("snd_1")
            var nav = probe.find(v, "nav")
            check("a row opens the swap's own screen", nav.depth, 2)
            var screen = nav.currentItem
            check("...titled the same", probe.find(screen, "swapDetailTitle").text, "Swap 1000 USDC for 0.33327 ETH")
            check("...with the minimum it was sent with", probe.find(screen, "swapDetailMin").value, "0.33161 ETH")
            check("...who asked, then the backend the sender attested", probe.find(screen, "swapDetailOrigin").value,
                  "uniswap_ui, through uniswap_backend")
            check("...and a row from before the backend names its origin alone", v.askedBy({ origin: "host" }), "host")
            check("...or nothing at all", v.askedBy({}), "—")
            check("...and both legs", probe.find(screen, "swapLegLabel_1").text, "2. Swap USDC for ETH on Uniswap V3")
            check("...each with its hash to copy", probe.find(screen, "swapLegHash_0").copyValue, "0xa0")

            console.log("")
            console.log("an empty and an unknown list are two different answers")
            v.back()
            fake.swapsJson = "[]"
            check("no swaps: said in words", probe.node("swapsEmpty").visible, true)
            fake.swapsJson = ""
            check("not read: an em-dash, never 'no swaps'", probe.node("swapsUnknownNote").text, "—")
            check("...and the empty line is down", probe.node("swapsEmpty").visible, false)

            console.log("")
            console.log("RESULT: " + (probe.failures ? probe.failures + " FAILED" : "ALL PASS"))
            Qt.exit(probe.failures ? 1 : 0)
        }
    }
}
