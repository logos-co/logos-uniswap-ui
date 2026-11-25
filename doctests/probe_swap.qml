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
    // Visible primary LogosButtons under an item: a LogosButton is what has both a variant and a labelItem.
    function primaries(o) {
        if (!o || o.visible === false) return 0
        var n = (o.variant === 0 && o.labelItem !== undefined) ? 1 : 0
        var kids = o.data !== undefined ? o.data : []
        for (var i = 0; i < kids.length; ++i) n += primaries(kids[i])
        return n
    }
    function networkSheetOpen() { probe.find(view.item, "networkSheet").open() }
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
    property var networkPicks: []

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
            // Settled after EIP-7708: the router's ether to the account is logged, and the
            // backend reads what arrived off it. Not the quote.
            received: "333100000000000000", receivedDisplay: "0.3331", receivedExact: "0.3331",
            swap: { kind: "swap", symbolIn: "USDC", symbolOut: "ETH", amountIn: "1000000000", decimalsIn: 6,
                    amountOut: "333277787035494084", decimalsOut: 18, amountOutMin: "331611398100316613",
                    route: { version: "V3", viaWeth: false, hops: [{ fee: 500 }] } },
            legs: [{ hash: "0xa0", leg: 0, status: "confirmed", label: "Approve USDC for Uniswap", to: probe.usdc },
                   { hash: "0xa1", leg: 1, status: "confirmed", label: "Swap USDC for ETH on Uniswap V3", to: probe.router }]
        }])
        property bool sweepingReceipts: false
        function refresh() {}
        function selectAccount(a) {}
        function selectNetwork(chainId) { var l = probe.networkPicks; l.push(chainId); probe.networkPicks = l }
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
            fee: { ok: true, feeCeilingWeiDisplay: "0.0004", nativeSymbol: "ETH", feeSource: "eip1559", nonce: 7,
                   maxFeePerGas: "1700000000", maxPriorityFeePerGas: "169400000", gasLimit: 226000,
                   legs: [{ gasLimit: 46000, label: "Approve USDC for Uniswap" },
                          { gasLimit: 180000, label: "Swap USDC for ETH on Uniswap V3" }] }
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
            console.log("the layout: the design system's page margin, and a centred column of 560")
            check("the tabs run the page's width, inside a 40px desktop margin", probe.node("tabs").width, 1000 - 2 * 40)
            check("the content column is capped at 560", probe.node("nav").width, 560)
            check("...and centred", probe.node("nav").x, (1000 - 2 * 40 - 560) / 2)

            console.log("")
            console.log("the network chip names this app's chain and opens the Network sheet")
            fake.networksJson = JSON.stringify([
                { chainId: 1, name: "Ethereum", nativeSymbol: "ETH", testnet: false },
                { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true }
            ])
            fake.activeNetworkJson = JSON.stringify(
                { chainId: 1, name: "Ethereum", nativeSymbol: "ETH", testnet: false })
            check("the chip names the chain", probe.node("chainChip").text, "Ethereum")
            check("...its row in the sheet is the one ticked", probe.inDialog("networkSheet", "networkRow_1").checked, true)
            check("...and no other", probe.inDialog("networkSheet", "networkRow_11155111").checked, false)
            probe.inDialog("networkSheet", "networkRow_11155111").clicked()
            check("a row asks the backend for its chain", JSON.stringify(probe.networkPicks), JSON.stringify([11155111]))
            fake.activeNetworkJson = JSON.stringify(
                { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true })
            check("the chip follows the published chain, saying it is a testnet", probe.node("chainChip").text, "Sepolia (testnet)")
            check("...and so does the sheet", probe.inDialog("networkSheet", "networkRow_11155111").checked, true)
            fake.networksJson = JSON.stringify([
                { chainId: 11155111, name: "Sepolia", nativeSymbol: "ETH", testnet: true }
            ])

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
            check("the button keeps its name", probe.node("swapButton").text, "Review swap")
            check("nothing to buy yet: the reason beside it asks for a token", probe.node("swapReason").text, "Select a token")
            check("...and is disabled", probe.node("swapButton").enabled, false)
            console.log("")
            console.log("the two cards read alike, and only the page's action is primary")
            check("no token to buy: its button is secondary", probe.node("buyTokenButton").variant, 1)
            check("...and says what it does", probe.node("buyTokenButton").text, "Select token")
            check("the token button is as tall as the amount field", probe.node("sellTokenButton").height,
                  probe.node("sellAmountField").height)
            check("the Buy amount is a field too, read-only", probe.node("buyAmountField").readOnly, true)
            check("the balance under the Sell field", probe.node("sellBalance").text, "Balance: 1.5")
            fake.selectedAccount = ""
            check("no account picked: the balance line says why it is empty", probe.node("sellBalance").text,
                  "Pick an account to see the balance")
            check("...and the reason beside the button asks for one", probe.node("swapReason").text, "Pick an account")
            check("...and no Max without an account", probe.node("sellMaxButton").visible, false)
            fake.selectedAccount = probe.me
            check("the flip control is a 32px button", probe.node("flipButton").size, 32)
            check("...not a flat ghost", probe.node("flipButton").flat, false)
            page.selectToken("buy", probe.usdcToken)
            probe.node("flipButton").clicked()
            check("a flip swaps the sides", page.sellSymbol + "/" + page.buySymbol, "USDC/ETH")
            probe.node("flipButton").clicked()
            check("...and back", page.sellSymbol + "/" + page.buySymbol, "ETH/USDC")
            check("a pair with no amount asks for one", probe.node("swapReason").text, "Enter an amount")
            page.selectToken("buy", probe.ethToken)
            check("the same token twice is refused", probe.node("swapReason").text, "Choose two different tokens")

            console.log("")
            console.log("1000 USDC for ETH: the form describes a request and the backend prices it")
            page.selectToken("sell", probe.usdcToken)
            page.selectToken("buy", probe.ethToken)
            var sellField = probe.node("sellAmountField")
            sellField.text = "1000"
            fake.quoteLoading = true
            check("the reason says it is pricing", probe.node("swapReason").text, "Pricing…")
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
            check("the buy card shows the quoted output", probe.node("buyAmountField").text, "0.33327")
            check("the rate line", probe.node("rateLine").text, "1 USDC = 0.000333278 ETH")
            check("the minimum received", probe.node("minReceivedRow").value, "0.33161 ETH")
            check("the price impact, as a percentage", probe.node("impactRow").value, "0.02%")
            check("the route", probe.node("routeRow").value, "Uniswap V3 0.05%")
            check("the pool fee", probe.node("feeTierRow").value, "0.05%")
            check("the approval, said before it is asked", probe.node("approvalRow").value, "Approve USDC first")
            check("the fee is a ceiling, never a price", probe.node("feeRow").value, "at most 0.0004 ETH (Market)")
            check("priced: no reason beside the button", probe.node("swapReason").text, "")
            check("...enabled", probe.node("swapButton").enabled, true)

            console.log("")
            console.log("the sender's figures, as the wallet shows them: each call's gas and nonce")
            check("each call's gas limit", probe.node("gasLimitRow").value, "46000 + 180000")
            check("the max fee, in gwei", probe.node("maxFeeRow").value, "1.7 gwei")
            check("the nonces the two calls take", probe.node("nonceRow").value, "7, 8")
            console.log("")
            console.log("the Fee block: the wallet's radios, each with what its tier pays per gas")
            check("Market is the tier on", probe.node("tierNormal").checked, true)
            check("...a radio, not a second primary button", probe.node("tierNormal").variant, undefined)
            check("no estimate where fee_module named none", probe.node("tierNormalEstimate").visible, false)
            fake.feeTiersJson = JSON.stringify({ source: "eip1559", baseFeePerGas: "1000000000",
                tiers: { slow: { maxFeePerGas: "1200000000" }, normal: { maxFeePerGas: "1700000000" },
                         fast: { maxFeePerGas: "2500000000" } } })
            check("Low's ceiling per gas", probe.node("tierSlowEstimate").text, "up to 1.2 gwei")
            check("Market's", probe.node("tierNormalEstimate").text, "up to 1.7 gwei")
            check("Fast's", probe.node("tierFastEstimate").text, "up to 2.5 gwei")
            probe.node("tierFast").clicked()
            check("a click picks the tier", page.tier, "fast")
            check("...and the request carries it", JSON.parse(probe.quoted[probe.quoted.length - 1]).tier, "fast")
            probe.node("tierNormal").clicked()
            probe.publishQuote({})
            check("one primary button on the page: the action", probe.primaries(page), 1)
            check("the kit's bare Advanced box is hidden under the disclosure", probe.node("advancedToggle").visible, false)
            check("the disclosure says what it opens", probe.node("swapAdvancedToggle").text,
                  "Advanced: slippage, deadline, gas and nonce")
            probe.node("swapAdvancedToggle").clicked()
            check("it opens the kit's fields", probe.node("advancedToggle").checked, true)
            check("...and slippage and the deadline", probe.node("advancedDeadlineField").visible, true)
            check("...at their values", probe.node("advancedDeadlineField").text, "30")
            probe.node("swapAdvancedToggle").clicked()
            check("and closes them", probe.node("advancedDeadlineField").visible, false)

            console.log("")
            console.log("and the Advanced section this app did not have")
            probe.node("advancedToggle").checked = true
            check("a gas limit per call, named for it", probe.node("gasLimitField_1").placeholderText,
                  "Swap USDC for ETH on Uniswap V3: gas limit (estimated 180000)")
            check("two transactions cannot be pinned to one nonce", probe.node("nonceField").readOnly, true)
            probe.node("gasLimitField_1").text = "250000"
            probe.node("maxPriorityFeeField").text = "2000000000"
            var custom = JSON.parse(probe.quoted[probe.quoted.length - 1])
            check("the swap's own limit goes out, the approval's left estimated", JSON.stringify(custom.gasLimits),
                  JSON.stringify([null, "250000"]))
            check("the tip as typed, with the max fee the quote suggested", custom.maxPriorityFeePerGas + " / " + custom.maxFeePerGas,
                  "2000000000 / 1700000000")
            check("and no nonce", custom.nonce, undefined)
            probe.node("gasLimitField_1").text = ""
            probe.node("maxPriorityFeeField").text = ""
            probe.node("advancedToggle").checked = false
            probe.publishQuote({})

            console.log("")
            console.log("the figures are withdrawn the moment the form changes")
            sellField.text = "1001"
            check("a changed amount unpairs the quote", probe.node("buyAmountField").text, "")
            check("...and the button no longer offers it", probe.node("swapButton").enabled, false)
            sellField.text = "1000"
            check("the same request pairs again", probe.node("buyAmountField").text, "0.33327")

            console.log("")
            console.log("what the quote can say against the swap")
            probe.publishQuote({ insufficientBalance: true })
            check("a balance short of the amount", probe.node("swapReason").text, "Insufficient USDC balance")
            probe.publishQuote({ fee: { ok: false, error: "the account cannot afford this: 0.001 ETH short" } })
            check("a fee the account cannot pay", probe.node("swapReason").text, "Not enough ETH for gas")
            check("...with the sender's words on screen", probe.node("feeErrorLabel").text, "Fee: the account cannot afford this: 0.001 ETH short")
            probe.publishQuote({ priceImpactBps: 350 })
            check("3.5% impact is a warning colour, not a gate", probe.node("swapReason").text, "")
            probe.publishQuote({ priceImpactBps: 800 })
            check("8% impact needs an acknowledgement", probe.node("swapReason").text, "Tick “I understand the price impact” first")
            check("...and the button waits for it", probe.node("swapButton").enabled, false)
            check("...beside a warning that says the figure", probe.node("impactWarning").visible, true)
            page.impactAcknowledged = true
            check("acknowledged, the swap is offered", probe.node("swapButton").enabled, true)
            sellField.text = "999"
            check("...and a changed form asks again", page.impactAcknowledged, false)
            sellField.text = "1000"
            fake.quoteJson = "{}"; fake.quoteRequestJson = ""
            fake.swapError = "no route found"
            check("no route, in the module's words", probe.node("swapReason").text, "No route")
            check("...and the reason is on screen", probe.node("swapErrorLabel").text, "no route found")
            fake.swapError = "no answer within 8699ms: operation timed out"
            check("any other refusal says the quote failed, not that a swap is on offer", probe.node("swapReason").text, "Could not quote")
            fake.swapError = ""
            probe.publishQuote({ fee: { ok: false, error: "the node did not answer" } })
            check("a fee that could not be priced for another reason says so", probe.node("swapReason").text, "Fee unavailable")
            probe.publishQuote({})
            fake.pendingRequestId = "snd_9"
            check("a swap awaiting a human holds the button", probe.node("swapReason").text, "Waiting for approval")
            check("...which still reads Review swap", probe.node("swapButton").text, "Review swap")
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
            console.log("an error stays where its action was taken")
            review.open()
            review.confirmed()
            check("Confirm waits on the backend", v.swapSubmitting, true)
            fake.swapError = "Rejected: the pool moved"
            check("the review says why, without the machine code", probe.inDialog("reviewDialog", "reviewError").text, "the pool moved")
            check("...and frees its Confirm", v.swapSubmitting, false)
            check("the page does not repeat it under the open review", probe.node("swapErrorLabel").visible, false)
            review.close()
            check("closed, the review forgets it", review.error, "")
            check("...and the page does not take it over", probe.node("swapErrorLabel").visible, false)
            fake.swapError = ""
            fake.swapError = "no route found"
            check("a quote's own refusal is the page's", probe.node("swapErrorLabel").text, "no route found")
            networkSheetOpen()
            check("...held back while a sheet is up", probe.node("swapErrorLabel").visible, false)
            probe.find(v, "networkSheet").close()
            fake.swapError = ""
            fake.lastError = "ReadFailed: the node did not answer"
            check("a failed read shows under the header, code stripped", probe.node("errorLabel").text, "the node did not answer")
            networkSheetOpen()
            check("...and not while a sheet is up", probe.node("errorRow").visible, false)
            probe.find(v, "networkSheet").close()
            check("...back once it closes", probe.node("errorRow").visible, true)
            fake.lastError = ""
            review.open()
            review.confirmed()
            v.submitTimedOut()
            check("a Confirm nobody answers does not hold the button", v.swapSubmitting, false)
            check("...and the review says so", probe.inDialog("reviewDialog", "reviewError").text,
                  "The swap did not answer. Nothing was sent; try again.")
            review.close()

            console.log("")
            console.log("the Activity tab shows this app's bundles, one card per swap")
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
            check("...and saying what it received, off the receipt",
                  String(probe.node("swapWhen_snd_1").text).indexOf("received 0.3331 ETH") > 0, true)
            check("an unmeasured swap claims nothing received", v.receivedLine({ swap: { symbolOut: "ETH" } }), "")
            check("the swap is a framed card", probe.node("swapRow_snd_1").contentItem !== undefined
                  && probe.node("swapRow_snd_1").background !== null, true)
            probe.node("swapDetails_snd_1").clicked()
            var nav = probe.find(v, "nav")
            check("its Details opens the swap's own screen", nav.depth, 2)
            var screen = nav.currentItem
            check("...titled the same", probe.find(screen, "swapDetailTitle").text, "Swap 1000 USDC for 0.33327 ETH")
            check("...with the minimum it was sent with", probe.find(screen, "swapDetailMin").value, "0.33161 ETH")
            check("...and what actually arrived", probe.find(screen, "swapDetailReceived").value, "0.3331 ETH")
            check("...shown, because the receipt said so", probe.find(screen, "swapDetailReceived").visible, true)
            check("...copying every digit", probe.find(screen, "swapDetailReceived").copyValue, "0.3331")
            check("...who asked, then the backend the sender attested", probe.find(screen, "swapDetailOrigin").value,
                  "uniswap_ui, through uniswap_backend")
            check("...and a row from before the backend names its origin alone", v.askedBy({ origin: "host" }), "host")
            check("...or nothing at all", v.askedBy({}), "—")
            check("...and both legs", probe.find(screen, "swapLegLabel_1").text, "2. Swap USDC for ETH on Uniswap V3")
            check("...each with its hash to copy", probe.find(screen, "swapLegHash_0").copyValue, "0xa0")

            console.log("")
            console.log("a swap no receipt log measured (ether out before Glamsterdam) says nothing")
            var unmeasured = JSON.parse(fake.swapsJson)
            delete unmeasured[0].received
            delete unmeasured[0].receivedDisplay
            delete unmeasured[0].receivedExact
            fake.swapsJson = JSON.stringify(unmeasured)
            check("no Received row: quoted is not received", probe.find(screen, "swapDetailReceived").visible, false)
            check("...and its row claims nothing", String(probe.node("swapWhen_snd_1").text).indexOf("received"), -1)

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
