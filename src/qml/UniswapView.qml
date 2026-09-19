import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Icons
import Logos.Theme

// The Uniswap app. One question per screen, as the wallet: sell one token, buy another,
// everything else under the two cards, and this app's network visible at all times. The
// network is chosen here from eth_rpc_module's enabled, in-scope chains.
//
// It holds no secret and sends nothing: uniswap_module quotes and builds, tx_sender_module
// sends, evm_signer_ui takes the human's yes — once, for every call of the swap. Every
// item showing a string this view did not author sets `textFormat: Text.PlainText`.
Item {
    id: root
    objectName: "uniswapRoot"
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("uniswap_ui")

    // Fed by the signal AND seeded: a view built after ui-host handed over never sees one.
    property bool ready: false
    Component.onCompleted: root.ready = root.backend !== null
                                        && logos.isViewModuleReady("uniswap_ui")
    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "uniswap_ui") root.ready = isReady && root.backend !== null
        }
    }

    property string lastCopiedValue: ""
    // From the click until the backend has either taken the swap or refused it. Both clear
    // it, or a refusal leaves the button dead with nothing on the page to revive it.
    property bool swapSubmitting: false
    property string approvalNote: ""
    property string intentNote: ""
    property string dismissedOutcome: ""

    readonly property var swapOutcome: root.ready ? j(backend.lastSwapOutcomeJson, "{}") : ({})
    readonly property var outcomeHashes: root.swapOutcome.hashes !== undefined
                                         ? root.swapOutcome.hashes : []
    function dismissOutcome() { root.dismissedOutcome = root.backend.lastSwapOutcomeJson }
    readonly property bool showOutcome: root.ready && !root.swapPending
        && backend.lastSwapOutcomeJson !== ""
        && backend.lastSwapOutcomeJson !== root.dismissedOutcome

    // Ask whoever provides a capability to take over. The provider declares these hand-offs,
    // so the user stays there and this callback only ever runs to report that nobody went.
    function askFor(intent, whenUnavailable) {
        root.intentNote = ""
        logos.request(intent, ({}), function (res) {
            if (res.ok || res.error === "cancelled") return
            root.intentNote = res.error === "unavailable"
                ? whenUnavailable
                : "That request did not go through (" + res.error + ")."
        })
    }

    // Codes that mean the intent path is CLOSED and no human is looking at the record; the
    // wallet's rule, verbatim, for the reasons written beside it there. `unavailable` is NOT
    // on the list: the signer may be openable by hand, and withdrawing there would delete the
    // record the user was just told to go and approve.
    function intentPathIsClosed(error) {
        return error === "bad_request" || error === "not_declared"
            || error === "timeout" || error === "cancelled"
    }

    // Point a signer at the swap now waiting on a human. The result is ADVISORY: the sender's
    // status is what settles the swap.
    function askToApprove() {
        var handle = root.ready ? root.backend.pendingApprovalHandle : ""
        if (handle === "") return
        root.approvalNote = ""
        logos.request("evm.signing.approve", ({ handle: handle }), function (res) {
            if (res.ok) return
            if (res.error === "cancelled") { root.backend.cancelSwap(); return }
            root.approvalNote = res.error === "unavailable"
                ? "Approve this swap in the Signer app to send it."
                : "Could not reach a signer (" + res.error + ")."
            if (root.intentPathIsClosed(res.error))
                root.backend.cancelSwap()
        })
    }

    Connections {
        target: root.ready ? root.backend : null
        function onPendingRequestIdChanged() {
            if (root.swapPending) {
                root.swapSubmitting = false
                reviewDialog.close()
            }
        }
        function onSwapErrorChanged() {
            if (root.backend.swapError.length > 0) root.swapSubmitting = false
        }
        function onPendingApprovalHandleChanged() {
            if (root.backend.pendingApprovalHandle !== "") root.askToApprove()
        }
        function onLastSwapOutcomeJsonChanged() {
            if (root.backend.lastSwapOutcomeJson === "") root.dismissedOutcome = ""
        }
    }

    onSelectedChanged: if (accountPicker) accountPicker.syncIndex()

    function j(text, fallback) {
        try { return JSON.parse(text && text.length ? text : fallback) }
        catch (e) { return JSON.parse(fallback) }
    }

    readonly property var net: ready ? j(backend.activeNetworkJson, "{}") : ({})
    readonly property var networks: ready ? j(backend.networksJson, "[]") : []
    readonly property var accounts: ready ? j(backend.accountsJson, "[]") : []
    readonly property var accountLabels: ready ? j(backend.accountLabelsJson, "{}") : ({})
    readonly property var accountWallets: ready ? j(backend.accountWalletsJson, "{}") : ({})
    readonly property var fees: ready ? j(backend.feeTiersJson, "{}") : ({})
    readonly property bool feeTiersLoading: ready && backend.feeTiersLoading
    readonly property bool feesPending: feeTiersLoading && root.fees.source === undefined
    readonly property var settings: ready ? j(backend.settingsJson, "{}") : ({})
    readonly property int slippageBps: settings.slippageBps !== undefined ? settings.slippageBps : 50
    readonly property int deadlineMins: settings.deadlineMins !== undefined ? settings.deadlineMins : 30

    readonly property var vp: ready ? j(backend.verifiedProxyJson, "{}") : ({})
    readonly property bool verificationOn: ready && vp.mode !== undefined && vp.mode !== "off"

    // ── scoped values: the ONLY place a scoped backend property is read ───────────
    readonly property bool scoped: ready && backend.scopedDataFresh
    readonly property bool dataLoading: ready && backend.dataLoading
    readonly property bool balancesKnown: scoped && backend.balancesJson.length > 0
    readonly property var balances: balancesKnown ? j(backend.balancesJson, "[]") : []
    readonly property string balancesRoute: balancesKnown ? backend.balancesRoute : ""
    readonly property bool tokensKnown: ready && backend.tokensJson.length > 0
    readonly property var tokens: tokensKnown ? j(backend.tokensJson, "[]") : []
    readonly property bool swapsKnown: scoped && backend.swapsJson.length > 0
    readonly property var swaps: swapsKnown ? j(backend.swapsJson, "[]") : []
    readonly property bool sweeping: swapsKnown && backend.sweepingReceipts
    readonly property var quote: scoped ? j(backend.quoteJson, "{}") : ({})
    readonly property string quoteRequest: scoped ? backend.quoteRequestJson : ""
    readonly property bool quoteStale: scoped && backend.quoteStale
    readonly property bool quoteLoading: ready && backend.quoteLoading

    // The catalogue, chain-scoped: the reply names the chain it answered for.
    readonly property bool catalogueKnown: ready && backend.catalogueJson.length > 0
    readonly property var catalogue: catalogueKnown ? j(backend.catalogueJson, "{}") : ({})
    readonly property bool catalogueForChain: catalogueKnown && catalogue.chainId === net.chainId
    readonly property var catalogueTokens: catalogueForChain && catalogue.tokens !== undefined
                                           ? catalogue.tokens : []
    readonly property bool catalogueLoading: ready && backend.catalogueLoading
    readonly property string catalogueError: catalogueForChain && catalogue.listError !== undefined
                                             ? String(catalogue.listError) : ""
    // More pages than are on screen: the answer's own word for it, and the next page loads as
    // the picker scrolls.
    readonly property bool catalogueHasMore: catalogueForChain && catalogue.hasMore === true
    readonly property int catalogueShown: catalogueForChain && typeof catalogue.shown === "number" ? catalogue.shown : -1
    readonly property int catalogueTotal: catalogueForChain && typeof catalogue.total === "number" ? catalogue.total : -1

    readonly property string netName: net.name !== undefined ? net.name : ""
    readonly property bool netKnown: netName.length > 0
    readonly property string nativeSymbol: net.nativeSymbol !== undefined ? net.nativeSymbol : ""
    readonly property bool isTestnet: net.testnet === true
    function networkLabel() { return netKnown ? netName + (isTestnet ? " (testnet)" : "") : "—" }
    function networkIndex() {
        for (var i = 0; i < networks.length; ++i)
            if (networks[i].chainId === net.chainId) return i
        return -1
    }
    function networkChoiceLabel(n) {
        var name = n.name !== undefined && String(n.name).length ? String(n.name) : "Chain " + n.chainId
        return name + (n.testnet === true ? " · TESTNET" : "")
    }
    readonly property bool swapPending: ready && backend.pendingRequestId.length > 0
    readonly property string selected: ready ? backend.selectedAccount : ""

    readonly property url iconArrowLeft: Qt.resolvedUrl("assets/arrow-left.svg")
    readonly property url iconTriangleDown: Qt.resolvedUrl("assets/triangle-down.svg")
    readonly property url iconRefresh: Qt.resolvedUrl("assets/refresh.svg")

    component HoverIcon: LogosIconButton {
        flat: true
        iconColor: isActive ? Theme.palette.text : Theme.palette.textTertiary
    }

    // ── helpers ───────────────────────────────────────────────────────────────────
    function sameHex(a, b) {
        if (!a || !b) return false
        return String(a).toLowerCase() === String(b).toLowerCase()
    }
    function shortAddr(a) {
        if (!a) return ""
        var s = String(a)
        return s.length > 12 ? s.substring(0, 6) + "…" + s.substring(s.length - 4) : s
    }
    function shortHash(h) {
        if (!h) return ""
        var s = String(h)
        return s.length > 14 ? s.substring(0, 8) + "…" + s.substring(s.length - 6) : s
    }
    function accountLabel(a) {
        if (!a) return ""
        var k = String(a).toLowerCase().replace(/^0x/, "")
        return accountLabels[k] !== undefined ? String(accountLabels[k]) : ""
    }
    // The wallet's rule: an account's own name, else its wallet's name and derivation
    // index, else nothing — never an invented "Account 2" that renumbers.
    function displayName(a) {
        var own = accountLabel(a)
        if (own.length) return own
        var w = a ? accountWallets[String(a).toLowerCase()] || accountWallets[a] : undefined
        if (w && w.wallet) return w.index !== undefined ? w.wallet + " #" + w.index : w.wallet
        return ""
    }
    function accountDisplay(a) {
        var n = displayName(a)
        return n.length ? n + " · " + shortAddr(a) : shortAddr(a)
    }
    function accountIndex(a) {
        for (var i = 0; i < accounts.length; ++i)
            if (sameHex(accounts[i], a)) return i
        return -1
    }
    function tokenKey(t) {
        if (!t) return ""
        if (t.native === true) return "native"
        if (typeof t.address === "string" && t.address.length > 0) return t.address.toLowerCase()
        return t.symbol ? "sym:" + t.symbol : ""
    }
    function tokenByKey(key) {
        for (var i = 0; i < tokens.length; ++i)
            if (tokenKey(tokens[i]) === key) return tokens[i]
        for (var k = 0; k < catalogueTokens.length; ++k)
            if (tokenKey(catalogueTokens[k]) === key) return catalogueTokens[k]
        return null
    }
    // What uniswap_module is told: ether is "ETH", a token is its contract.
    function tokenWire(t) { return !t ? "" : t.native === true ? "ETH" : String(t.address || "") }
    function balanceField(t, field) {
        if (!t) return ""
        for (var i = 0; i < balances.length; ++i) {
            var b = balances[i]
            var match = t.native === true ? b.native === true
                      : (typeof b.address === "string" && sameHex(b.address, t.address))
            if (match && b[field] !== undefined) return String(b[field])
        }
        return ""
    }
    function balanceDisplay(t) { var v = balanceField(t, "display"); return v.length ? v : "—" }
    function balanceExact(t) { return balanceField(t, "exact") }
    // The wallet's provenance vocabulary, never the word "verified".
    function tokenSource(t) {
        if (!t) return "unknown"
        if (t.native === true) return "native"
        if (t.builtin === true) return "builtin"
        var s = typeof t.source === "string" ? t.source : ""
        return ["allowlist", "custom", "downloaded", "embedded", "enabled"].indexOf(s) >= 0
             ? s : "unknown"
    }
    function tokenSourceLabel(s) {
        if (s === "native") return "Network coin"
        if (s === "builtin") return "Built in"
        if (s === "allowlist") return "Wallet list"
        if (s === "custom") return "Added here"
        if (s === "downloaded") return "Fetched list"
        if (s === "embedded") return "Uniswap list"
        if (s === "enabled") return "Turned on here"
        return "Unknown source"
    }
    function tokenSourceColor(s) {
        if (s === "native" || s === "builtin" || s === "allowlist")
            return Theme.palette.textSecondary
        if (s === "unknown") return Theme.palette.error
        return Theme.palette.warning
    }
    function isEnabledToken(t) {
        for (var i = 0; i < tokens.length; ++i)
            if (tokenKey(tokens[i]) === tokenKey(t)) return true
        return false
    }
    // The picker's rows, appended a page at a time. A ListView handed a NEW array scrolls
    // back to its top, and a page lands while the user is at the bottom — so the model behind
    // the picker only grows in place, and starts over for a new answer.
    ListModel { id: pickerModel }
    onPickerTokensChanged: syncPickerModel()
    function syncPickerModel() {
        var rows = root.pickerTokens
        var grows = root.catalogue.appended === true && pickerModel.count > 0
                    && pickerModel.count <= rows.length
        if (!grows) pickerModel.clear()
        for (var i = pickerModel.count; i < rows.length; ++i)
            pickerModel.append(root.pickerRow(rows[i]))
    }
    // One row with every role present: a ListModel types a role on first sight, and the
    // native row has no address. The token itself is looked up again by key when picked.
    function pickerRow(t) {
        return { key: root.tokenKey(t), symbol: String(t.symbol || ""), name: String(t.name || ""),
                 address: typeof t.address === "string" ? t.address : "",
                 native: t.native === true, builtin: t.builtin === true,
                 source: typeof t.source === "string" ? t.source : "" }
    }
    // The picker's rows: the wallet's tokens first (they have balances), the catalogue after,
    // each contract once.
    readonly property var pickerTokens: {
        var seen = ({}), out = []
        for (var i = 0; i < tokens.length; ++i) {
            var k = tokenKey(tokens[i])
            if (!k || seen[k]) continue
            seen[k] = true
            out.push(tokens[i])
        }
        for (var c = 0; c < catalogueTokens.length; ++c) {
            var ck = tokenKey(catalogueTokens[c])
            if (!ck || seen[ck]) continue
            seen[ck] = true
            out.push(catalogueTokens[c])
        }
        return out
    }
    function routeLine(r) {
        if (!r || r.version === undefined) return ""
        var s = "Uniswap " + r.version
        if (r.version === "V3" && r.hops !== undefined && r.hops.length) {
            var fees = []
            for (var i = 0; i < r.hops.length; ++i)
                if (r.hops[i].fee !== undefined) fees.push((r.hops[i].fee / 10000) + "%")
            if (fees.length) s += " " + fees.join(" → ")
        }
        return r.viaWeth === true ? s + " · via WETH" : s
    }
    function impactText(bps) {
        if (bps === undefined || bps === null) return "—"
        return (bps / 100).toFixed(2) + "%"
    }
    function routeNote(r) {
        if (r === "verified") return "proof-backed."
        if (r === "proxied" || r === "direct") return "forwarded on trust, not proved."
        return "of unknown standing."
    }
    function chipState(verdict, route) {
        if (verdict.mode === undefined) return "hidden"
        if (verdict.mode === "off") return "hidden"
        if (verdict.mode === "unknown") return "unknown"
        return route === "verified" ? "verified" : "unverified"
    }
    function chipText(s) {
        return s === "verified" ? "Balances verified"
             : s === "unknown" ? "Verification unknown" : "Not verified"
    }
    function chipColor(s) {
        return s === "verified" ? Theme.palette.success
             : s === "unknown" ? Theme.palette.warning : Theme.palette.textSecondary
    }
    // eth_rpc's closed action set, word for word: an unknown word renders no hint at all.
    function actionHint(a) {
        if (a === "wait") return "The proxy is catching up. Figures return when it has."
        if (a === "install_or_load") return "Install and start the Verified Proxy module, then reopen this app."
        if (a === "open_verified_proxy") return "Open Verified Proxy and press Start."
        if (a === "restart_or_reload") return "Open Verified Proxy, press Stop then Start. If that does not help, reload the app."
        return ""
    }
    function statusText(s) { return s || "—" }
    function statusColor(s) {
        if (s === "confirmed") return Theme.palette.success
        if (s === "failed") return Theme.palette.error
        if (s === "stalled" || s === "blocked") return Theme.palette.warning
        return Theme.palette.textSecondary
    }
    // Who asked for a swap: the module that asked the backend, then the backend itself, which
    // is what the sender attests. A row recorded before the backend existed has no `via`.
    function askedBy(b) {
        var origin = b && b.origin !== undefined ? String(b.origin) : ""
        var via = b && b.via !== undefined ? String(b.via) : ""
        if (via.length && origin.length) return via + ", through " + origin
        return origin.length ? origin : "—"
    }
    function swapTitle(b) {
        var m = b && b.swap ? b.swap : ({})
        if (m.amountIn !== undefined && m.symbolIn !== undefined && m.symbolOut !== undefined)
            return "Swap " + units(m.amountIn, m.decimalsIn) + " " + m.symbolIn
                 + " for " + units(m.amountOut, m.decimalsOut) + " " + m.symbolOut
        return b && b.label ? String(b.label) : "Swap"
    }
    // A bounded token-unit display of a base-unit string, for rows whose backend carried no
    // display string. Truncated, never rounded up; five places; "<0.00001" for a dust amount.
    function units(base, decimals) {
        var s = String(base || "")
        if (!/^[0-9]+$/.test(s)) return "—"
        var d = decimals === undefined ? 18 : decimals
        while (s.length <= d) s = "0" + s
        var whole = s.substring(0, s.length - d)
        var frac = s.substring(s.length - d).replace(/0+$/, "")
        if (frac.length > 5) frac = frac.substring(0, 5).replace(/0+$/, "")
        if (whole === "0" && frac.length === 0) return d > 0 && /[1-9]/.test(s) ? "<0.00001" : "0"
        return frac.length ? whole + "." + frac : whole
    }
    function txWhen(ts) {
        if (!ts) return ""
        return Qt.formatDateTime(new Date(ts * 1000), "MMM d, HH:mm")
    }

    // ── navigation ────────────────────────────────────────────────────────────────
    function selectTab(i) {
        if (nav.depth > 1) nav.popToIndex(0, StackView.Immediate)
        tabs.currentIndex = i
        pages.currentIndex = i
    }
    function openSwapDetail(requestId) {
        if (nav.depth > 1) nav.popToIndex(0, StackView.Immediate)
        nav.pushItem(swapDetailComponent, { requestId: requestId })
    }
    function back() { if (nav.depth > 1) nav.popCurrentItem() }
    function swapByRequestId(id) {
        for (var i = 0; i < swaps.length; ++i)
            if (swaps[i].requestId === id) return swaps[i]
        return null
    }

    // ── the swap form's decisions, as functions the probe can call ───────────────
    // The button's one line. Ordered the way Uniswap's own is: what is missing first, then
    // what cannot be paid, then what could not be priced, then the swap itself.
    function swapButtonText(state) {
        if (state === "noAccount") return "No account"
        if (state === "selectToken") return "Select a token"
        if (state === "enterAmount") return "Enter an amount"
        if (state === "sameToken") return "Choose two different tokens"
        if (state === "insufficient") return "Insufficient " + swapPage.sellSymbol + " balance"
        if (state === "noGas") return "Not enough " + (root.nativeSymbol || "ETH") + " for gas"
        if (state === "noRoute") return "No route"
        if (state === "error") return "Could not quote"
        if (state === "feeError") return "Fee unavailable"
        if (state === "pricing") return "Pricing…"
        if (state === "acknowledge") return "Swap anyway"
        if (state === "pending") return "Waiting for approval"
        return root.netKnown ? "Swap on " + root.networkLabel() : "Swap"
    }
    // The state, from what the form and the quote say. Pure over its arguments, so the probe
    // drives it with a fabricated backend and asserts every row of the table.
    function swapState(haveAccount, sell, buy, amountUnits, q, loading, error, pending, acknowledged) {
        if (!haveAccount) return "noAccount"
        if (!sell || !buy) return "selectToken"
        if (root.tokenKey(sell) === root.tokenKey(buy)) return "sameToken"
        if (!amountUnits || !amountUnits.length || /^[0.]*$/.test(amountUnits)) return "enterAmount"
        if (pending) return "pending"
        if (q.ok === true) {
            if (q.insufficientBalance === true) return "insufficient"
            if (q.fee !== undefined && q.fee.ok !== true) {
                var e = q.fee.error !== undefined ? String(q.fee.error) : ""
                return /afford|balance|cover|insufficient/i.test(e) ? "noGas" : "feeError"
            }
            if (q.priceImpactBps !== undefined && q.priceImpactBps !== null
                && q.priceImpactBps >= root.severeImpactBps && !acknowledged) return "acknowledge"
            return "ready"
        }
        if (error && error.length) return /no route/i.test(error) ? "noRoute" : "error"
        return loading ? "pricing" : "unpriced"
    }
    // Uniswap's own thresholds: a warning colour from 3%, an acknowledgement from 5%.
    readonly property int warnImpactBps: 300
    readonly property int severeImpactBps: 500

    component TokenGlyph: Item {
        id: glyph
        property string symbol: ""
        implicitWidth: 28
        implicitHeight: 28
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Theme.colors.getColor(Theme.palette.primary, 0.18)
            LogosText {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: (glyph.symbol || "?").substring(0, 1)
                color: Theme.palette.primary
                font.weight: Theme.typography.weightMedium
            }
        }
    }

    component AccountPicker: LogosComboBox {
        id: picker
        property var addresses: []
        readonly property string currentAddress:
            currentIndex >= 0 && currentIndex < addresses.length ? addresses[currentIndex] : ""
        model: addresses
        displayText: root.accountDisplay(picker.currentAddress)
        delegate: ItemDelegate {
            id: accountItem
            width: picker.popupListView ? picker.popupListView.width : picker.width
            objectName: "accountRow_" + index
            highlighted: picker.highlightedIndex === index
            background: Rectangle {
                color: accountItem.highlighted ? Theme.palette.surface : "transparent"
            }
            HoverHandler { cursorShape: accountItem.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
            contentItem: ColumnLayout {
                spacing: 0
                LogosText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    textFormat: Text.PlainText
                    text: root.displayName(modelData)
                    elide: Text.ElideRight
                }
                LogosText {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: root.shortAddr(modelData)
                    color: Theme.palette.textSecondary
                    font.family: Theme.typography.mono
                    font.pixelSize: Theme.typography.secondaryText
                    elide: Text.ElideNone
                }
            }
        }
    }

    component DetailRow: RowLayout {
        id: row
        property string label: ""
        property string value: ""
        property string copyValue: ""
        property bool mono: false
        property color valueColor: Theme.palette.text
        Layout.fillWidth: true
        spacing: Theme.spacing.medium
        LogosText {
            text: row.label
            color: Theme.palette.textSecondary
            font.pixelSize: Theme.typography.secondaryText
            Layout.preferredWidth: 132
        }
        Item { Layout.fillWidth: true }
        LogosText {
            visible: row.copyValue.length === 0
            textFormat: Text.PlainText
            text: row.value
            color: row.valueColor
            font.family: row.mono ? Theme.typography.mono : Theme.typography.publicSans
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
        RowLayout {
            visible: row.copyValue.length > 0
            spacing: Theme.spacing.small
            LogosSelectableText {
                text: row.value
                font.family: row.mono ? Theme.typography.mono : Theme.typography.publicSans
            }
            LogosCopyButton {
                ToolTip.text: "Copy"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                objectName: row.objectName.length > 0 ? row.objectName + "Copy" : ""
                value: row.copyValue
                onCopied: function (v) { root.lastCopiedValue = v }
            }
        }
    }

    // One of the two cards: what you sell, what you buy.
    component SwapCard: LogosFrame {
        id: card
        property string heading: ""
        property var token: null
        property bool editable: true
        property alias amountText: amountField.text
        property string amountDisplay: ""
        property string sideName: ""
        signal pickToken()
        signal maxClicked()
        Layout.fillWidth: true
        contentItem: ColumnLayout {
            spacing: Theme.spacing.tiny
            LogosText {
                textFormat: Text.PlainText
                text: card.heading
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosTextField {
                    id: amountField
                    objectName: card.sideName + "AmountField"
                    Layout.fillWidth: true
                    visible: card.editable
                    placeholderText: "0"
                    font.pixelSize: Theme.typography.pageTitleText
                }
                LogosText {
                    objectName: card.sideName + "AmountLabel"
                    Layout.fillWidth: true
                    visible: !card.editable
                    textFormat: Text.PlainText
                    text: card.amountDisplay.length ? card.amountDisplay : "0"
                    color: card.amountDisplay.length ? Theme.palette.text : Theme.palette.textTertiary
                    font.pixelSize: Theme.typography.pageTitleText
                    elide: Text.ElideRight
                }
                LogosButton {
                    objectName: card.sideName + "TokenButton"
                    text: card.token ? String(card.token.symbol) : "Select token"
                    variant: card.token ? LogosButton.Variant.Secondary : LogosButton.Variant.Primary
                    onClicked: card.pickToken()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                visible: card.token !== null
                LogosText {
                    objectName: card.sideName + "Balance"
                    textFormat: Text.PlainText
                    text: card.token ? "Balance: " + root.balanceDisplay(card.token) : ""
                    color: Theme.palette.textSecondary
                    font.pixelSize: Theme.typography.secondaryText
                }
                LogosButton {
                    objectName: card.sideName + "MaxButton"
                    visible: card.editable && card.token !== null
                             && root.balanceExact(card.token).length > 0
                    text: "Max"
                    onClicked: card.maxClicked()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.medium
        spacing: Theme.spacing.small

        // ── header: the account and the chain, over every screen ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            AccountPicker {
                id: accountPicker
                objectName: "accountPicker"
                Layout.preferredWidth: 220
                addresses: root.accounts
                enabled: root.ready && root.accounts.length > 0
                onActivated: if (root.ready) root.backend.selectAccount(root.accounts[currentIndex])
                function syncIndex() { currentIndex = root.accountIndex(root.selected) }
                Component.onCompleted: syncIndex()
                onAddressesChanged: syncIndex()
            }
            HoverIcon {
                objectName: "manageAccountsButton"
                size: 32
                iconSize: 16
                iconSource: LogosIcons.grid
                ToolTip.text: "Accounts"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                onClicked: root.askFor("evm.accounts.manage", "No app on this device manages accounts.")
            }
            Item { Layout.fillWidth: true }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosSelectableText {
                objectName: "addressLabel"
                text: root.shortAddr(root.selected)
                color: Theme.palette.textSecondary
                font.family: Theme.typography.mono
            }
            LogosCopyButton {
                ToolTip.text: "Copy"
                ToolTip.visible: hovered
                ToolTip.delay: 400
                objectName: "addressCopyButton"
                value: root.selected
                onCopied: function (v) { root.lastCopiedValue = v }
            }
            Item { Layout.fillWidth: true }
            LogosComboBox {
                id: chainPicker
                objectName: "chainPicker"
                Layout.preferredWidth: 190
                model: root.networks.map(function (n) { return root.networkChoiceLabel(n) })
                enabled: root.ready && root.networks.length > 0
                onActivated: if (root.ready && currentIndex >= 0)
                    root.backend.selectNetwork(root.networks[currentIndex].chainId)
                function syncIndex() { currentIndex = root.networkIndex() }
                Component.onCompleted: syncIndex()
                onModelChanged: syncIndex()
                // loadNetwork publishes the choices before it publishes the chosen row. The
                // first publication therefore cannot find the choice yet; follow the second
                // one as well or the control keeps currentIndex=-1 while the rest of the view
                // is already reading Ethereum.
                Connections {
                    target: root
                    function onNetChanged() { chainPicker.syncIndex() }
                }
            }
            LogosBadge {
                objectName: "verifiedChip"
                readonly property string chip: root.chipState(root.vp, root.balancesRoute)
                visible: root.ready && chip !== "hidden"
                text: root.chipText(chip)
                color: root.chipColor(chip)
            }
        }

        LogosFrame {
            objectName: "verifiedBanner"
            Layout.fillWidth: true
            visible: root.ready && root.vp.blocking === true
            contentItem: ColumnLayout {
                spacing: Theme.spacing.tiny
                LogosText {
                    objectName: "verifiedBannerMessage"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.error
                    text: root.vp.message !== undefined ? root.vp.message : ""
                }
                LogosText {
                    objectName: "verifiedBannerAction"
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    text: root.actionHint(root.vp.action)
                }
            }
        }

        RowLayout {
            objectName: "errorRow"
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.ready && root.backend.lastError.length > 0
            spacing: 8
            LogosText {
                objectName: "errorLabel"
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.palette.error
                text: root.ready ? root.backend.lastError : ""
            }
            LogosButton {
                objectName: "errorRetryButton"
                enabled: root.ready
                text: "Retry"
                onClicked: root.backend.refresh()
            }
        }
        LogosText {
            objectName: "intentNote"
            Layout.fillWidth: true
            visible: root.intentNote.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.palette.textSecondary
            text: root.intentNote
        }

        // ── three sections ──
        LogosTabBar {
            id: tabs
            objectName: "tabs"
            Layout.fillWidth: true
            onCurrentIndexChanged: root.selectTab(currentIndex)
            LogosTabButton { text: "Swap" }
            LogosTabButton { text: "Activity" }
            LogosTabButton { text: "Settings" }
        }

        LogosStackView {
            id: nav
            objectName: "nav"
            Layout.fillWidth: true
            Layout.fillHeight: true

            initialItem: Item {
                objectName: "home"
                StackLayout {
                    id: pages
                    objectName: "pages"
                    anchors.fill: parent

                    // ── Swap ──
                    Item {
                        id: swapPage
                        objectName: "swapPage"

                        property var sell: null
                        property var buy: null
                        readonly property string sellSymbol: sell ? String(sell.symbol) : ""
                        readonly property string buySymbol: buy ? String(buy.symbol) : ""
                        // Which card the picker is choosing for.
                        property string picking: "sell"
                        // The 5% acknowledgement, per quote: it is reset when the figures move.
                        property bool impactAcknowledged: false
                        property string tier: "normal"

                        function selectToken(side, t) {
                            if (side === "sell") swapPage.sell = t
                            else swapPage.buy = t
                        }
                        // The first enabled token that is not the other side, so a fresh screen
                        // already sells the network coin.
                        function seedSell() {
                            if (swapPage.sell === null && root.tokens.length > 0)
                                swapPage.sell = root.tokens[0]
                        }
                        function flip() {
                            var s = swapPage.sell
                            swapPage.sell = swapPage.buy
                            swapPage.buy = s
                            sellCard.amountText = swapForm.q.amountOutExact !== undefined
                                                  ? String(swapForm.q.amountOutExact) : ""
                        }
                        function clearForm() {
                            sellCard.amountText = ""
                            swapPage.impactAcknowledged = false
                        }
                        onVisibleChanged: {
                            if (!root.ready) return
                            if (visible) { seedSell(); swapForm.reprice() }
                            root.backend.setQuoteAutoRefresh(visible)
                        }
                        Connections {
                            target: root
                            function onTokensChanged() { swapPage.seedSell() }
                        }

                        LogosScrollView {
                            id: swapScroll
                            anchors.fill: parent
                            contentWidth: availableWidth

                            ColumnLayout {
                                id: swapForm
                                objectName: "swapForm"
                                width: swapScroll.availableWidth
                                spacing: Theme.spacing.small

                                function request() {
                                    var r = {
                                        from: root.selected,
                                        tokenIn: root.tokenWire(swapPage.sell),
                                        tokenOut: root.tokenWire(swapPage.buy),
                                        symbolIn: swapPage.sellSymbol,
                                        symbolOut: swapPage.buySymbol,
                                        decimalsIn: swapPage.sell && swapPage.sell.decimals !== undefined
                                                    ? swapPage.sell.decimals : 18,
                                        decimalsOut: swapPage.buy && swapPage.buy.decimals !== undefined
                                                     ? swapPage.buy.decimals : 18,
                                        amountUnits: sellCard.amountText.trim(),
                                        tier: swapPage.tier,
                                        slippageBps: root.slippageBps,
                                        deadlineMins: root.deadlineMins
                                    }
                                    return JSON.stringify(r)
                                }
                                readonly property string formRequest: request()
                                readonly property var q: root.quoteRequest.length > 0
                                                         && root.quoteRequest === swapForm.formRequest
                                                         ? root.quote : ({})
                                readonly property string state: root.swapState(
                                    root.selected.length > 0, swapPage.sell, swapPage.buy,
                                    sellCard.amountText.trim(), swapForm.q, root.quoteLoading,
                                    root.ready ? root.backend.swapError : "", root.swapPending,
                                    swapPage.impactAcknowledged)
                                readonly property bool severe: q.priceImpactBps !== undefined
                                    && q.priceImpactBps !== null && q.priceImpactBps >= root.severeImpactBps
                                readonly property bool warn: q.priceImpactBps !== undefined
                                    && q.priceImpactBps !== null && q.priceImpactBps >= root.warnImpactBps

                                function reprice() { if (root.ready) root.backend.quote(swapForm.formRequest) }
                                onFormRequestChanged: {
                                    swapPage.impactAcknowledged = false
                                    if (swapPage.visible) reprice()
                                }

                                SwapCard {
                                    id: sellCard
                                    objectName: "sellCard"
                                    sideName: "sell"
                                    heading: "Sell"
                                    token: swapPage.sell
                                    editable: true
                                    onPickToken: { swapPage.picking = "sell"; tokenPicker.open() }
                                    onMaxClicked: sellCard.amountText = root.balanceExact(swapPage.sell)
                                }
                                HoverIcon {
                                    objectName: "flipButton"
                                    Layout.alignment: Qt.AlignHCenter
                                    size: 32
                                    iconSize: 16
                                    iconSource: LogosIcons.arrowRightDouble
                                    rotation: 90
                                    ToolTip.text: "Swap sides"
                                    ToolTip.visible: hovered
                                    ToolTip.delay: 400
                                    onClicked: swapPage.flip()
                                }
                                SwapCard {
                                    id: buyCard
                                    objectName: "buyCard"
                                    sideName: "buy"
                                    heading: "Buy"
                                    token: swapPage.buy
                                    editable: false
                                    amountDisplay: swapForm.q.amountOutDisplay !== undefined
                                                   ? String(swapForm.q.amountOutDisplay) : ""
                                    onPickToken: { swapPage.picking = "buy"; tokenPicker.open() }
                                }

                                // The rate, and everything under it.
                                LogosText {
                                    objectName: "rateLine"
                                    visible: swapForm.q.ok === true && swapForm.q.rate !== undefined
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    text: "1 " + swapPage.sellSymbol + " = " + swapForm.q.rate + " " + swapPage.buySymbol
                                }
                                ColumnLayout {
                                    objectName: "quoteDetails"
                                    visible: swapForm.q.ok === true
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.tiny
                                    DetailRow {
                                        objectName: "minReceivedRow"
                                        label: "Minimum received"
                                        value: (swapForm.q.amountOutMinDisplay || "—") + " " + swapPage.buySymbol
                                    }
                                    DetailRow {
                                        objectName: "impactRow"
                                        label: "Price impact"
                                        value: root.impactText(swapForm.q.priceImpactBps)
                                        valueColor: swapForm.severe ? Theme.palette.error
                                                  : swapForm.warn ? Theme.palette.warning : Theme.palette.text
                                    }
                                    DetailRow {
                                        objectName: "routeRow"
                                        label: "Route"
                                        value: root.routeLine(swapForm.q.route)
                                    }
                                    DetailRow {
                                        objectName: "feeTierRow"
                                        label: "Pool fee"
                                        value: swapForm.q.feeBps !== undefined ? (swapForm.q.feeBps / 100) + "%" : "—"
                                    }
                                    DetailRow {
                                        objectName: "slippageRow"
                                        label: "Max slippage"
                                        value: (root.slippageBps / 100) + "%"
                                    }
                                    DetailRow {
                                        objectName: "approvalRow"
                                        visible: swapForm.q.needsApproval === true
                                        label: "Approval"
                                        value: swapForm.q.approval === "resetThenSet"
                                               ? "Reset and approve " + swapPage.sellSymbol + " first"
                                               : "Approve " + swapPage.sellSymbol + " first"
                                    }
                                    // "at most", never "the fee": a ceiling the user is not charged.
                                    DetailRow {
                                        objectName: "feeRow"
                                        label: "Network fee"
                                        value: swapForm.q.fee !== undefined && swapForm.q.fee.feeCeilingWeiDisplay !== undefined
                                               ? "at most " + swapForm.q.fee.feeCeilingWeiDisplay + " "
                                                 + (swapForm.q.fee.nativeSymbol || root.nativeSymbol)
                                                 + " (" + swapPage.tier + ")"
                                               : "—"
                                    }
                                    LogosText {
                                        objectName: "feeErrorLabel"
                                        visible: swapForm.q.fee !== undefined && swapForm.q.fee.ok !== true
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        wrapMode: Text.WordWrap
                                        color: Theme.palette.error
                                        text: swapForm.q.fee !== undefined && swapForm.q.fee.error !== undefined
                                              ? "Fee: " + swapForm.q.fee.error : ""
                                    }
                                    LogosText {
                                        objectName: "feeSourceLabel"
                                        visible: text.length > 0
                                        textFormat: Text.PlainText
                                        color: Theme.palette.textSecondary
                                        font.pixelSize: Theme.typography.secondaryText
                                        text: swapForm.q.fee !== undefined && swapForm.q.fee.feeSource !== undefined
                                              ? "Fee basis: " + swapForm.q.fee.feeSource : ""
                                    }
                                    LogosText {
                                        objectName: "quoteRouteNote"
                                        visible: root.verificationOn
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        color: Theme.palette.textSecondary
                                        font.pixelSize: Theme.typography.secondaryText
                                        text: "Quote figures are " + root.routeNote(swapForm.q.rpcRoute)
                                    }
                                }

                                // Fee tiers, as the wallet's Send page names them.
                                RowLayout {
                                    id: tierGroup
                                    spacing: Theme.spacing.tiny
                                    LogosText {
                                        text: "Fee"
                                        color: Theme.palette.textSecondary
                                        font.pixelSize: Theme.typography.secondaryText
                                    }
                                    LogosButton {
                                        objectName: "tierSlow"; text: "Low"
                                        variant: swapPage.tier === "slow" ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                                        onClicked: swapPage.tier = "slow"
                                    }
                                    LogosButton {
                                        objectName: "tierNormal"; text: "Market"
                                        variant: swapPage.tier === "normal" ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                                        onClicked: swapPage.tier = "normal"
                                    }
                                    LogosButton {
                                        objectName: "tierFast"; text: "Fast"
                                        variant: swapPage.tier === "fast" ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                                        onClicked: swapPage.tier = "fast"
                                    }
                                }

                                LogosText {
                                    objectName: "quotePricingNote"
                                    visible: root.quoteLoading && swapForm.q.ok !== true
                                    color: Theme.palette.textSecondary
                                    text: "Pricing…"
                                }
                                LogosText {
                                    objectName: "quoteStaleNote"
                                    visible: root.quoteStale && swapForm.q.ok === true
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.warning
                                    text: "The quote could not be refreshed. The swap is re-quoted when you confirm it."
                                }
                                LogosText {
                                    objectName: "impactWarning"
                                    visible: swapForm.severe
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.error
                                    text: "This swap moves the price by " + root.impactText(swapForm.q.priceImpactBps)
                                          + ". You would receive much less than the current rate."
                                }
                                LogosCheckbox {
                                    id: impactCheck
                                    objectName: "impactAcknowledge"
                                    visible: swapForm.severe
                                    text: "I understand the price impact"
                                    checked: swapPage.impactAcknowledged
                                    onToggled: swapPage.impactAcknowledged = checked
                                }
                                LogosText {
                                    objectName: "swapErrorLabel"
                                    visible: root.ready && root.backend.swapError.length > 0
                                    Layout.fillWidth: true
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WordWrap
                                    color: Theme.palette.error
                                    text: root.ready ? root.backend.swapError : ""
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Item { Layout.fillWidth: true }
                                    LogosSpinner {
                                        objectName: "swapSubmitSpinner"
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 18
                                        implicitHeight: 18
                                        visible: root.swapSubmitting
                                        running: visible
                                        ringColor: Theme.palette.textSecondary
                                    }
                                    LogosButton {
                                        objectName: "swapButton"
                                        Layout.preferredWidth: 220
                                        variant: LogosButton.Variant.Primary
                                        text: root.swapButtonText(swapForm.state)
                                        enabled: root.ready && !root.swapSubmitting
                                                 && swapForm.state === "ready"
                                        onClicked: reviewDialog.open()
                                    }
                                }
                            }
                        }
                    }

                    // ── Activity: this app's swaps ──
                    Item {
                        objectName: "activityPage"
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.spacing.tiny
                            LogosText {
                                objectName: "activityNote"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "Swaps made from this app on this account and network. "
                                      + "The wallet's Activity shows them too, beside its own sends."
                            }
                            LogosText {
                                objectName: "sweepNote"
                                visible: root.sweeping
                                Layout.fillWidth: true
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "Checking for confirmations…"
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                LogosText {
                                    objectName: "swapsEmpty"
                                    anchors.centerIn: parent
                                    visible: root.swapsKnown && root.swaps.length === 0
                                    text: "No swaps yet"
                                    color: Theme.palette.textSecondary
                                }
                                ColumnLayout {
                                    objectName: "swapsUnknown"
                                    anchors.centerIn: parent
                                    spacing: Theme.spacing.small
                                    visible: !root.swapsKnown
                                    LogosSpinner {
                                        Layout.alignment: Qt.AlignHCenter
                                        implicitWidth: 24
                                        implicitHeight: 24
                                        visible: root.dataLoading
                                        running: visible
                                        ringColor: Theme.palette.textSecondary
                                    }
                                    LogosText {
                                        objectName: "swapsUnknownNote"
                                        Layout.alignment: Qt.AlignHCenter
                                        text: root.dataLoading ? "Loading swaps…" : "—"
                                        color: Theme.palette.textSecondary
                                    }
                                }
                                LogosListView {
                                    objectName: "swapsList"
                                    anchors.fill: parent
                                    visible: root.swaps.length > 0
                                    model: root.swaps
                                    spacing: 0
                                    delegate: LogosItemDelegate {
                                        id: swapRow
                                        objectName: "swapRow_" + modelData.requestId
                                        width: ListView.view ? ListView.view.width : 0
                                        topPadding: Theme.spacing.small
                                        bottomPadding: Theme.spacing.small
                                        implicitHeight: rowBody.implicitHeight + topPadding + bottomPadding
                                        onClicked: root.openSwapDetail(modelData.requestId)
                                        contentItem: ColumnLayout {
                                            id: rowBody
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                LogosText {
                                                    objectName: "swapTitle_" + modelData.requestId
                                                    textFormat: Text.PlainText
                                                    text: root.swapTitle(modelData)
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                LogosBadge {
                                                    objectName: "swapStatus_" + modelData.requestId
                                                    text: root.statusText(modelData.status)
                                                    color: root.statusColor(modelData.status)
                                                }
                                            }
                                            LogosText {
                                                objectName: "swapWhen_" + modelData.requestId
                                                textFormat: Text.PlainText
                                                color: Theme.palette.textSecondary
                                                font.pixelSize: Theme.typography.secondaryText
                                                text: root.txWhen(modelData.timestamp)
                                                      + (modelData.legs !== undefined && modelData.legs.length > 1
                                                         ? " · " + modelData.legs.length + " transactions" : "")
                                            }
                                        }
                                        Rectangle {
                                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                            height: 1
                                            color: Theme.palette.borderTertiaryMuted
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Settings ──
                    Item {
                        objectName: "settingsPage"
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.medium
                            spacing: Theme.spacing.small

                            LogosText {
                                text: "Max slippage"
                                font.weight: Theme.typography.weightMedium
                            }
                            RowLayout {
                                spacing: Theme.spacing.tiny
                                LogosButton {
                                    objectName: "slippageAuto"
                                    text: "Auto (0.5%)"
                                    variant: root.settings.autoSlippage === true
                                             ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                                    onClicked: root.backend.setSettings(JSON.stringify({ autoSlippage: true, slippageBps: 50 }))
                                }
                                LogosTextField {
                                    id: slippageField
                                    objectName: "slippageField"
                                    Layout.preferredWidth: 120
                                    placeholderText: "Custom %"
                                    text: root.settings.autoSlippage === true ? "" : (root.slippageBps / 100).toString()
                                    // Applied when the field is left, not on every keystroke: "1." is
                                    // not a slippage yet. LogosTextField wraps a TextInput and exposes
                                    // it, so the signal is the inner item's.
                                    function apply() {
                                        var pct = parseFloat(text)
                                        if (isNaN(pct) || !root.ready) return
                                        root.backend.setSettings(JSON.stringify({ autoSlippage: false,
                                                                                  slippageBps: Math.round(pct * 100) }))
                                    }
                                    Connections {
                                        target: slippageField.textInput
                                        function onEditingFinished() { slippageField.apply() }
                                    }
                                }
                            }
                            LogosText {
                                objectName: "slippageNote"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: root.slippageBps > 100 ? Theme.palette.warning : Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: root.slippageBps > 100
                                      ? "A high slippage lets a swap settle far below the quote."
                                      : "The swap reverts if the rate moves more than this before it lands."
                            }

                            LogosText {
                                text: "Transaction deadline"
                                font.weight: Theme.typography.weightMedium
                            }
                            RowLayout {
                                spacing: Theme.spacing.tiny
                                LogosTextField {
                                    id: deadlineField
                                    objectName: "deadlineField"
                                    Layout.preferredWidth: 120
                                    text: root.deadlineMins.toString()
                                    function apply() {
                                        var m = parseInt(text)
                                        if (isNaN(m) || !root.ready) return
                                        root.backend.setSettings(JSON.stringify({ deadlineMins: m }))
                                    }
                                    Connections {
                                        target: deadlineField.textInput
                                        function onEditingFinished() { deadlineField.apply() }
                                    }
                                }
                                LogosText { text: "minutes"; color: Theme.palette.textSecondary }
                            }

                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.palette.borderTertiaryMuted }

                            LogosItemDelegate {
                                objectName: "tokenListsEntry"
                                Layout.fillWidth: true
                                text: "Token lists"
                                onClicked: root.askFor("evm.token_lists.configure",
                                                       "No app on this device manages token lists.")
                            }
                            LogosItemDelegate {
                                objectName: "accountsEntry"
                                Layout.fillWidth: true
                                text: "Accounts"
                                onClicked: root.askFor("evm.accounts.manage",
                                                       "No app on this device manages accounts.")
                            }
                            LogosText {
                                objectName: "settingsNote"
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: "This app's network is selected in the header from the enabled device scope. "
                                      + "Slippage, deadline, and that selection are kept for this session."
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }
        }
    }

    // ── a swap's own screen ──────────────────────────────────────────────────────
    Component {
        id: swapDetailComponent
        Item {
            id: swapDetail
            objectName: "swapDetailPage"
            property string requestId: ""
            readonly property var bundle: root.swapByRequestId(requestId) || ({})
            readonly property var meta: bundle.swap !== undefined ? bundle.swap : ({})
            readonly property var legs: bundle.legs !== undefined ? bundle.legs : []

            LogosScrollView {
                anchors.fill: parent
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width
                    spacing: Theme.spacing.small
                    RowLayout {
                        Layout.fillWidth: true
                        HoverIcon {
                            objectName: "swapDetailBackButton"
                            size: 32
                            iconSize: 16
                            iconSource: root.iconArrowLeft
                            onClicked: root.back()
                        }
                        LogosText {
                            objectName: "swapDetailTitle"
                            textFormat: Text.PlainText
                            text: root.swapTitle(swapDetail.bundle)
                            font.pixelSize: Theme.typography.panelTitleText
                            font.weight: Theme.typography.weightMedium
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        LogosBadge {
                            objectName: "swapDetailStatus"
                            text: root.statusText(swapDetail.bundle.status)
                            color: root.statusColor(swapDetail.bundle.status)
                        }
                    }
                    LogosFrame {
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.tiny
                            DetailRow {
                                objectName: "swapDetailSold"
                                label: "Sold"
                                value: root.units(swapDetail.meta.amountIn, swapDetail.meta.decimalsIn) + " " + (swapDetail.meta.symbolIn || "")
                            }
                            DetailRow {
                                objectName: "swapDetailBought"
                                label: "Quoted"
                                value: root.units(swapDetail.meta.amountOut, swapDetail.meta.decimalsOut) + " " + (swapDetail.meta.symbolOut || "")
                            }
                            DetailRow {
                                objectName: "swapDetailMin"
                                label: "Minimum"
                                value: root.units(swapDetail.meta.amountOutMin, swapDetail.meta.decimalsOut) + " " + (swapDetail.meta.symbolOut || "")
                            }
                            DetailRow {
                                objectName: "swapDetailRoute"
                                label: "Route"
                                value: root.routeLine(swapDetail.meta.route)
                            }
                            DetailRow {
                                objectName: "swapDetailOrigin"
                                label: "Asked by"
                                value: root.askedBy(swapDetail.bundle)
                            }
                        }
                    }
                    LogosText {
                        text: "Transactions"
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Repeater {
                        model: swapDetail.legs
                        LogosFrame {
                            Layout.fillWidth: true
                            contentItem: ColumnLayout {
                                spacing: Theme.spacing.tiny
                                RowLayout {
                                    Layout.fillWidth: true
                                    LogosText {
                                        objectName: "swapLegLabel_" + index
                                        textFormat: Text.PlainText
                                        text: (index + 1) + ". " + (modelData.label || "")
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    LogosBadge {
                                        objectName: "swapLegStatus_" + index
                                        text: root.statusText(modelData.status)
                                        color: root.statusColor(modelData.status)
                                    }
                                }
                                DetailRow {
                                    objectName: "swapLegHash_" + index
                                    label: "Hash"
                                    mono: true
                                    value: modelData.hash ? root.shortHash(modelData.hash) : "—"
                                    copyValue: modelData.hash || ""
                                }
                                DetailRow {
                                    objectName: "swapLegTo_" + index
                                    label: "Contract"
                                    mono: true
                                    value: root.shortAddr(modelData.to)
                                    copyValue: modelData.to || ""
                                }
                                DetailRow {
                                    objectName: "swapLegFee_" + index
                                    label: "Fee"
                                    value: modelData.feeWeiDisplay !== undefined
                                           ? modelData.feeWeiDisplay + " " + (modelData.nativeSymbol || "")
                                           : modelData.feeCeilingWeiDisplay !== undefined
                                             ? "up to " + modelData.feeCeilingWeiDisplay + " " + (modelData.nativeSymbol || "")
                                             : "—"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── the token picker ─────────────────────────────────────────────────────────
    LogosDialog {
        id: tokenPicker
        objectName: "tokenPicker"
        title: swapPage.picking === "sell" ? "Sell which token?" : "Buy which token?"
        anchors.centerIn: parent
        width: 460
        onOpened: { pickerSearch.text = ""; root.backend.searchTokens("") }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosSearchBar {
                id: pickerSearch
                objectName: "tokenPickerSearch"
                Layout.fillWidth: true
                placeholderText: "Search by name, symbol or address"
                onTextChanged: pickerDebounce.restart()
                Timer {
                    id: pickerDebounce
                    interval: 250
                    onTriggered: if (root.ready) root.backend.searchTokens(pickerSearch.text.trim())
                }
            }
            LogosText {
                objectName: "tokenPickerNote"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: root.catalogueError.length ? Theme.palette.error : Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                text: root.catalogueError.length ? "The token list could not be read: " + root.catalogueError
                    : root.catalogueLoading ? "Searching…"
                    : root.catalogueHasMore ? "Showing " + root.catalogueShown + " of " + root.catalogueTotal
                                              + " matches — scroll for more, or keep typing to narrow."
                    : "Tokens the wallet shows come first, with their balances; the rest are from the "
                      + "token lists the wallet trusts. A token's name proves nothing about it."
            }
            LogosListView {
                objectName: "tokenPickerList"
                Layout.fillWidth: true
                Layout.preferredHeight: 320
                clip: true
                model: pickerModel
                // The next page, asked for once per answer as its end comes into view; the
                // backend ignores the ask while a call is live or once the answer is complete.
                property int askedAt: -1
                onContentYChanged: {
                    if (!root.catalogueHasMore || root.catalogueLoading) return
                    if (contentHeight - contentY - height > 240) return
                    if (askedAt === root.catalogueShown) return
                    askedAt = root.catalogueShown
                    if (root.ready) root.backend.loadMoreCatalogue()
                }
                delegate: LogosItemDelegate {
                    id: pickRow
                    // The ListModel row, read by role: a ListModel delegate has no pickRow.row
                    // on Qt 6.9. The token handed to the form is the original object, found
                    // by key, not this row.
                    readonly property var row: model
                    objectName: "tokenPick_" + row.key
                    width: ListView.view.width
                    implicitHeight: 52
                    onClicked: {
                        swapPage.selectToken(swapPage.picking, root.tokenByKey(row.key))
                        tokenPicker.close()
                    }
                    contentItem: RowLayout {
                        spacing: Theme.spacing.small
                        TokenGlyph { symbol: pickRow.row.symbol || "" }
                        ColumnLayout {
                            spacing: 0
                            Layout.fillWidth: true
                            RowLayout {
                                spacing: Theme.spacing.tiny
                                LogosText {
                                    textFormat: Text.PlainText
                                    text: pickRow.row.symbol || ""
                                    font.weight: Theme.typography.weightMedium
                                }
                                LogosText {
                                    textFormat: Text.PlainText
                                    text: root.tokenSourceLabel(root.tokenSource(pickRow.row))
                                    color: root.tokenSourceColor(root.tokenSource(pickRow.row))
                                    font.pixelSize: Theme.typography.secondaryText
                                }
                            }
                            LogosText {
                                textFormat: Text.PlainText
                                text: (pickRow.row.name || "") + (pickRow.row.native === true ? "" : "  " + root.shortAddr(pickRow.row.address))
                                color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        LogosText {
                            textFormat: Text.PlainText
                            visible: root.isEnabledToken(pickRow.row)
                            text: root.balanceDisplay(pickRow.row)
                            color: Theme.palette.textSecondary
                        }
                    }
                }
            }
        }
    }

    // ── review, before anything is asked of the sender ───────────────────────────
    LogosDialog {
        id: reviewDialog
        objectName: "reviewDialog"
        title: "Review swap"
        anchors.centerIn: parent
        width: 460
        readonly property var q: swapForm.q
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            DetailRow {
                objectName: "reviewPay"
                label: "You pay"
                value: (reviewDialog.q.amountInDisplay || "—") + " " + swapPage.sellSymbol
            }
            DetailRow {
                objectName: "reviewReceive"
                label: "You receive"
                value: (reviewDialog.q.amountOutDisplay || "—") + " " + swapPage.buySymbol
            }
            DetailRow {
                objectName: "reviewMin"
                label: "At least"
                value: (reviewDialog.q.amountOutMinDisplay || "—") + " " + swapPage.buySymbol
            }
            DetailRow {
                objectName: "reviewImpact"
                label: "Price impact"
                value: root.impactText(reviewDialog.q.priceImpactBps)
            }
            DetailRow {
                objectName: "reviewFee"
                label: "Network fee"
                value: reviewDialog.q.fee !== undefined && reviewDialog.q.fee.feeCeilingWeiDisplay !== undefined
                       ? "at most " + reviewDialog.q.fee.feeCeilingWeiDisplay + " "
                         + (reviewDialog.q.fee.nativeSymbol || root.nativeSymbol) : "—"
            }
            LogosText {
                text: "Transactions to approve"
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
            }
            Repeater {
                model: reviewDialog.q.calls !== undefined ? reviewDialog.q.calls : []
                LogosText {
                    objectName: "reviewCall_" + index
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    text: (index + 1) + ". " + (modelData.label || modelData.kind) + " · " + root.shortAddr(modelData.to)
                }
            }
            LogosText {
                objectName: "reviewNote"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                text: "The signer asks once for all of them. Nothing is sent until it says yes."
            }
            LogosText {
                objectName: "reviewError"
                visible: root.ready && root.backend.swapError.length > 0
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.palette.error
                text: root.ready ? root.backend.swapError : ""
            }
            RowLayout {
                Layout.fillWidth: true
                LogosButton {
                    objectName: "reviewCancel"
                    text: "Back"
                    onClicked: reviewDialog.close()
                }
                Item { Layout.fillWidth: true }
                LogosSpinner {
                    implicitWidth: 18
                    implicitHeight: 18
                    visible: root.swapSubmitting
                    running: visible
                    ringColor: Theme.palette.textSecondary
                }
                LogosButton {
                    objectName: "reviewConfirm"
                    variant: LogosButton.Variant.Primary
                    text: "Confirm swap"
                    enabled: root.ready && !root.swapSubmitting && !root.swapPending
                    onClicked: {
                        root.swapSubmitting = true
                        root.backend.submitSwap(swapForm.formRequest)
                    }
                }
            }
        }
    }

    // ── pending approval ─────────────────────────────────────────────────────────
    LogosDialog {
        objectName: "pendingDialog"
        title: "Waiting for approval"
        anchors.centerIn: parent
        visible: root.swapPending
        contentItem: ColumnLayout {
            LogosText {
                objectName: "pendingLabel"
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: root.approvalNote.length > 0
                      ? root.approvalNote
                      : "Waiting for this swap to be approved."
            }
            LogosText {
                objectName: "pendingPollingNote"
                visible: root.ready && root.backend.swapPolling
                color: Theme.palette.textSecondary
                font.pixelSize: Theme.typography.secondaryText
                text: "Sending…"
            }
            LogosButton {
                objectName: "cancelSwapButton"
                text: "Cancel swap"
                onClicked: root.backend.cancelSwap()
            }
        }
    }

    // ── what the last swap came to ───────────────────────────────────────────────
    LogosDialog {
        objectName: "swapOutcomeDialog"
        title: root.swapOutcome.status === "broadcast" ? "Sent" : "Not sent"
        anchors.centerIn: parent
        visible: root.showOutcome
        contentItem: ColumnLayout {
            LogosText {
                objectName: "swapOutcomeLabel"
                Layout.maximumWidth: 420
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: {
                    var o = root.swapOutcome
                    if (o.status === "broadcast")
                        return root.outcomeHashes.length > 1
                             ? "Sent to the network: " + root.outcomeHashes.length + " transactions."
                             : "Sent to the network."
                    if (o.status === "rejected")  return "The signer rejected this swap."
                    if (o.status === "cancelled") return "This swap was cancelled."
                    if (o.status === "stuck") return "The broadcast did not answer. The swap may still be on chain; check Activity before trying again."
                    if (o.reason !== undefined && o.reason.length) return o.reason
                    return "This swap did not go out."
                }
            }
            Repeater {
                model: root.outcomeHashes
                RowLayout {
                    objectName: "swapOutcomeHashRow_" + index
                    spacing: Theme.spacing.small
                    LogosSelectableText {
                        text: root.shortHash(modelData)
                        color: Theme.palette.textSecondary
                        font.family: Theme.typography.mono
                    }
                    LogosCopyButton {
                        ToolTip.text: "Copy"
                        ToolTip.visible: hovered
                        ToolTip.delay: 400
                        objectName: "swapOutcomeCopy_" + index
                        value: modelData
                        onCopied: function (v) { root.lastCopiedValue = v }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosButton {
                    objectName: "swapOutcomeDismiss"
                    text: "Done"
                    onClicked: { root.dismissOutcome(); swapPage.clearForm() }
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "swapOutcomeViewActivity"
                    visible: root.swapOutcome.status === "broadcast"
                    text: "View in Activity"
                    onClicked: { root.dismissOutcome(); swapPage.clearForm(); root.selectTab(1) }
                }
            }
        }
    }
}
