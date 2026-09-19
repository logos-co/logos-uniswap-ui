#include "uniswap_ui_backend.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

// The generated umbrella carrying `struct LogosModules` — without it `modules()` is an
// incomplete type and every dependency call fails to compile.
#include "logos_sdk.h"

namespace {

constexpr int kSendPollMs = 1500;
constexpr int kPendingPollMs = 5000;
constexpr int kVerifiedPollMs = 5000;
constexpr int kMaxSilentPolls = 3;
// One mainnet block. A quote re-priced faster than the chain moves learns nothing new.
constexpr int kQuotePollMs = 12000;
// Rows per page of the catalogue. The rest follows as the picker scrolls; nothing is cut.
constexpr int kCataloguePage = 100;

QString failure(const QString &why)
{
    return toJson(QJsonObject{{QStringLiteral("ok"), false}, {QStringLiteral("error"), why}});
}

} // namespace

UniswapUiBackend::UniswapUiBackend()
{
    m_settings = QJsonObject{{QStringLiteral("slippageBps"), 50},
                             {QStringLiteral("autoSlippage"), true},
                             {QStringLiteral("deadlineMins"), 30}};

    m_dataLane.budgetMs = kTwoCallBudgetMs;
    m_dataLane.setLoading = [this](bool on) { setDataLoading(on); };
    m_dataLane.rerun = [this] { loadBalancesAndSwaps(); };

    m_quoteLane.budgetMs = kSwapClaimBudgetMs;
    m_quoteLane.setLoading = [this](bool on) { setQuoteLoading(on); };
    m_quoteLane.rerun = [this] {
        const bool wasEdit = m_quoteAgainInteractive;
        m_quoteAgainInteractive = false;
        runQuote(m_quoteRequest, wasEdit);
    };

    m_catalogueLane.budgetMs = kOneCallBudgetMs;
    m_catalogueLane.setLoading = [this](bool on) { setCatalogueLoading(on); };
    m_catalogueLane.rerun = [this] { runCatalogueSearch(); };
}

bool UniswapUiBackend::failed(const QString &reply, const QString &context)
{
    if (replyOk(reply))
        return false;
    setLastError(refusal(reply, context));
    return true;
}

Selection UniswapUiBackend::shown() const
{
    return selectionOf(selectedAccount(), activeNetworkJson());
}

ScopedState UniswapUiBackend::scopeSnapshot() const
{
    ScopedState s;
    s.at = shown();
    s.fresh = scopedDataFresh();
    s.balances = balancesJson();
    s.balancesRoute = balancesRoute();
    s.quote = quoteJson();
    s.quoteRequest = quoteRequestJson();
    s.quoteStale = quoteStale();
    s.swapError = swapError();
    s.swaps = swapsJson();
    s.tokens = tokensJson();
    s.catalogue = catalogueJson();
    s.feeTiers = feeTiersJson();
    s.verifiedProxy = verifiedProxyJson();
    return s;
}

void UniswapUiBackend::publishScope(const ScopedState &s)
{
    setScopedDataFresh(s.fresh);
    setBalancesJson(s.balances);
    setBalancesRoute(s.balancesRoute);
    setQuoteJson(s.quote);
    setQuoteRequestJson(s.quoteRequest);
    setQuoteStale(s.quoteStale);
    setSwapError(s.swapError);
    setSwapsJson(s.swaps);
    setTokensJson(s.tokens);
    setCatalogueJson(s.catalogue);
    setFeeTiersJson(s.feeTiers);
    setVerifiedProxyJson(s.verifiedProxy);
}

void UniswapUiBackend::publishSelection(const QString &account, const QString &networkJson)
{
    ScopedState s = scopeSnapshot();
    const Selection to = selectionOf(account, networkJson);
    const bool chainMoved = s.at.chainId != to.chainId;
    if (enterScope(s, to)) {
        ++m_dataGen;
        ++m_quoteGen;
        publishScope(s);
    }
    if (chainMoved)
        m_vpSilent = 0;
    UniswapUiSimpleSource::setSelectedAccount(account);
    UniswapUiSimpleSource::setActiveNetworkJson(networkJson);
}

bool UniswapUiBackend::adoptChain(int chainId)
{
    if (chainId == shown().chainId)
        return false;
    const QJsonArray all = QJsonDocument::fromJson(networksJson().toUtf8()).array();
    for (const QJsonValue &v : all) {
        const QJsonObject n = v.toObject();
        if (n.value(QStringLiteral("chainId")).toInt() == chainId) {
            setActiveNetworkJson(toJson(n));
            return true;
        }
    }
    setActiveNetworkJson(QStringLiteral("{\"chainId\":%1}").arg(chainId));
    return true;
}

bool UniswapUiBackend::beginLane(AsyncLane &lane, quint64 *slot)
{
    if (!takeLane(lane, slot))
        return false;
    lane.setLoading(true);
    QTimer::singleShot(lane.budgetMs + 1, this, [this, &lane] {
        if (!lane.busy())
            handOnLane(lane);
    });
    return true;
}

void UniswapUiBackend::handOnLane(AsyncLane &lane)
{
    if (laneFinish(lane) == LaneStep::Rerun)
        lane.rerun();
    else
        lane.setLoading(false);
}

bool UniswapUiBackend::beginClaim(InFlight &claim, quint64 *slot, const SetLoading &setLoading,
                                  int budgetMs)
{
    if (!claim.take(budgetMs, slot))
        return false;
    setLoading(true);
    QTimer::singleShot(budgetMs + 1, this, [this, &claim, setLoading] {
        if (!claim.busy())
            setLoading(false);
    });
    return true;
}

void UniswapUiBackend::setSelectedAccount(QString address)
{
    publishSelection(address, activeNetworkJson());
}

void UniswapUiBackend::setActiveNetworkJson(QString networkJson)
{
    publishSelection(selectedAccount(), networkJson);
}

void UniswapUiBackend::refreshSoon()
{
    QTimer::singleShot(0, this, [this] { refresh(); });
}

void UniswapUiBackend::surfaceSwapError(const QString &error)
{
    ScopedState s = scopeSnapshot();
    s.swapError = error;
    publishScope(s);
}

void UniswapUiBackend::applyVerifiedProxy(const QString &verdictJson)
{
    ScopedState s = scopeSnapshot();
    const VerdictApplied v = applyVerdict(s, verdictJson, m_vpSilent, kMaxSilentPolls);
    m_vpSilent = v.silent;
    publishScope(s);
    if (!v.poll)
        m_vpPoll.stop();
    else if (!m_vpPoll.isActive())
        m_vpPoll.start();
}

void UniswapUiBackend::onContextReady()
{
    setSettingsJson(toJson(m_settings));

    m_sendPoll.setInterval(kSendPollMs);
    QObject::connect(&m_sendPoll, &QTimer::timeout, this, [this] { pollSwap(); });
    m_pendingPoll.setInterval(kPendingPollMs);
    QObject::connect(&m_pendingPoll, &QTimer::timeout, this, [this] { refreshPending(); });
    m_vpPoll.setInterval(kVerifiedPollMs);
    QObject::connect(&m_vpPoll, &QTimer::timeout, this, [this] { pollVerifiedProxy(); });
    m_quotePoll.setInterval(kQuotePollMs);
    QObject::connect(&m_quotePoll, &QTimer::timeout, this, [this] {
        // A swap awaiting a human is settled, not being priced.
        if (m_quoteRequest.isEmpty() || !pendingRequestId().isEmpty())
            return;
        runQuote(m_quoteRequest, false);
    });

    // The backend relays what moved underneath it. Event callbacks re-enter on a clean stack;
    // none performs another module call inline.
    modules().uniswap_backend.onNetworks_changed([this](int) { refreshSoon(); });
    modules().uniswap_backend.onAccounts_changed([this](int) { refreshSoon(); });
    modules().uniswap_backend.onTokens_changed([this](int chainId) {
        if (chainId != shown().chainId)
            return;
        refreshSoon();
        runCatalogueSearch();
    });
    // A swap in flight moved, a receipt landed, or a row was written — the wallet's rows
    // included, so the re-read is checked against the selection on screen.
    modules().uniswap_backend.onSwap_status_changed([this](QString requestId) {
        if (requestId == pendingRequestId())
            QTimer::singleShot(0, this, [this] { pollSwap(); });
    });
    modules().uniswap_backend.onSwaps_changed([this](QString address) {
        if (address.isEmpty() || address.compare(selectedAccount(), Qt::CaseInsensitive) == 0)
            QTimer::singleShot(0, this, [this] { loadBalancesAndSwaps(); });
    });

    refresh();
}

void UniswapUiBackend::loadNetwork()
{
    const QString all = modules().uniswap_backend.networks();
    if (failed(all, QStringLiteral("networks"))) {
        setNetworksJson(QStringLiteral("[]"));
        setActiveNetworkJson(QStringLiteral("{}"));
        if (!m_networkRetry) {
            m_networkRetry = true;
            QTimer::singleShot(kVerifiedPollMs, this, [this] {
                m_networkRetry = false;
                refresh();
            });
        }
        if (!m_vpPoll.isActive())
            m_vpPoll.start();
        return;
    }

    const QJsonArray choices = parseObject(all).value(QStringLiteral("networks")).toArray();
    setNetworksJson(toJson(choices));
    const int chosen = chooseChain(choices, shown().chainId);
    if (chosen == 0) {
        setActiveNetworkJson(QStringLiteral("{}"));
    } else if (adoptChain(chosen)) {
        m_refreshAgain = true;
    }

    if (shown().chainId == 0)
        return;
    const QString tokens = modules().uniswap_backend.tokens(shown().chainId);
    ScopedState s = scopeSnapshot();
    const Applied t = applyTokens(s, tokens);
    publishScope(s);
    if (!t.error.isEmpty())
        setLastError(t.error);
}

void UniswapUiBackend::loadAccounts()
{
    const QString reply = modules().uniswap_backend.accounts();
    if (failed(reply, QStringLiteral("accounts")))
        return;
    setAccountsJson(member(reply, "accounts"));
    // Names are a courtesy the backend omits when the keystore could not give them.
    const QJsonObject names = parseObject(reply);
    if (names.contains(QStringLiteral("labels")))
        setAccountLabelsJson(member(reply, "labels"));
    if (names.contains(QStringLiteral("wallets")))
        setAccountWalletsJson(member(reply, "wallets"));

    const QJsonArray list = QJsonDocument::fromJson(accountsJson().toUtf8()).array();
    const bool stillThere = std::any_of(list.begin(), list.end(), [this](const QJsonValue &v) {
        return v.toString().compare(selectedAccount(), Qt::CaseInsensitive) == 0;
    });
    if (!stillThere)
        setSelectedAccount(list.isEmpty() ? QString() : list.first().toString());
}

void UniswapUiBackend::loadBalancesAndSwaps()
{
    if (selectedAccount().isEmpty()) {
        ScopedState s = scopeSnapshot();
        applyNoAccount(s);
        publishScope(s);
        setSweep(false);
        setDataLoading(false);
        return;
    }
    quint64 slot = 0;
    if (!beginLane(m_dataLane, &slot))
        return;

    const quint64 gen = m_dataGen;
    const QString who = selectedAccount();
    const int chainId = shown().chainId;
    modules().uniswap_backend.balancesAsyncResult(chainId, who, QString(),
        [this, gen, who, chainId, slot](logos::AsyncResult<QString> bal) {
            if (!m_dataLane.owns(slot))
                return;
            if (gen == m_dataGen) {
                ScopedState s = scopeSnapshot();
                const Applied a = applyBalances(s, bal.ok() ? bal.value : QString());
                publishScope(s);
                if (!a.error.isEmpty())
                    setLastError(a.error);
            }
            modules().uniswap_backend.swapsAsyncResult(who, chainId,
                [this, gen, slot](logos::AsyncResult<QString> hist) {
                    m_dataLane.release(slot);
                    if (!m_dataLane.owns(slot))
                        return;
                    if (gen == m_dataGen) {
                        ScopedState s = scopeSnapshot();
                        const SwapsApplied h = applySwaps(s, hist.ok() ? hist.value : QString());
                        if (h.sweep != SweepVerdict::Unchanged)
                            setSweep(h.sweep == SweepVerdict::Run);
                        publishScope(s);
                    }
                    handOnLane(m_dataLane);
                },
                Timeout(kCallBudgetMs));
        },
        Timeout(kCallBudgetMs));
}

void UniswapUiBackend::setSweep(bool due)
{
    if (!due)
        m_pendingPoll.stop();
    else if (!m_pendingPoll.isActive())
        m_pendingPoll.start();
    setSweepingReceipts(due);
}

void UniswapUiBackend::loadFeeTiers()
{
    quint64 slot = 0;
    if (!beginClaim(m_feesInFlight, &slot, [this](bool on) { setFeeTiersLoading(on); }))
        return;
    const quint64 gen = m_dataGen;
    modules().uniswap_backend.fee_tiersAsyncResult(shown().chainId,
        [this, gen, slot](logos::AsyncResult<QString> res) {
            m_feesInFlight.release(slot);
            if (!m_feesInFlight.isCurrent(slot) || gen != m_dataGen)
                return;
            ScopedState s = scopeSnapshot();
            applyFeeTiers(s, res.ok() ? res.value : QString());
            publishScope(s);
            setFeeTiersLoading(false);
        },
        Timeout(kCallBudgetMs));
}

void UniswapUiBackend::refresh()
{
    if (m_inFlight) {
        m_refreshAgain = true;
        return;
    }
    m_inFlight = true;
    setLastError(QString());

    loadNetwork();
    loadAccounts();
    loadBalancesAndSwaps();
    loadFeeTiers();
    // Also what starts the verdict poll: nothing else does on a healthy start.
    refreshVerifiedProxy();

    m_inFlight = false;
    if (m_refreshAgain) {
        m_refreshAgain = false;
        refreshSoon();
    }
}

void UniswapUiBackend::selectAccount(QString address)
{
    setSelectedAccount(address);
    loadBalancesAndSwaps();
}

void UniswapUiBackend::selectNetwork(int chainId)
{
    if (!adoptChain(chainId))
        return;
    refresh();
}

void UniswapUiBackend::refreshSwaps()
{
    loadBalancesAndSwaps();
}

void UniswapUiBackend::searchTokens(QString query)
{
    m_catalogueQuery = query;
    m_catalogueChain = shown().chainId;
    m_catalogueOffset = 0;
    runCatalogueSearch();
}

void UniswapUiBackend::loadMoreCatalogue()
{
    // The next page of the answer on screen. Nothing while a call is live — the picker asks
    // again as it scrolls — and nothing once the answer said it was complete.
    if (m_catalogueLane.busy())
        return;
    const QJsonObject cur = parseObject(catalogueJson());
    if (!cur.value(QStringLiteral("hasMore")).toBool())
        return;
    m_catalogueOffset = cur.value(QStringLiteral("tokens")).toArray().size();
    runCatalogueSearch();
}

void UniswapUiBackend::runCatalogueSearch()
{
    quint64 slot = 0;
    if (!beginLane(m_catalogueLane, &slot))
        return;
    const quint64 gen = m_dataGen;
    const int offset = m_catalogueOffset;
    const QString query = m_catalogueQuery;
    // ASYNC, and the query goes to the backend: the embedded Uniswap list is thousands of
    // rows, so matching it here would mean pulling all of them across the wire.
    modules().uniswap_backend.catalogueAsyncResult(
        m_catalogueChain, m_catalogueQuery, offset, kCataloguePage,
        [this, gen, slot, offset, query](logos::AsyncResult<QString> res) {
            m_catalogueLane.release(slot);
            if (!m_catalogueLane.owns(slot))
                return;
            // A page for a question the user has since changed adds nothing: the re-run
            // queued behind this call asks the new one from its first row.
            const bool stalePage = offset > 0 && query != m_catalogueQuery;
            if (gen == m_dataGen && !stalePage) {
                ScopedState s = scopeSnapshot();
                const QString reply = res.ok() ? res.value : QString();
                const Applied a = offset == 0 ? applyCatalogue(s, reply)
                                              : applyCataloguePage(s, reply, offset);
                publishScope(s);
                if (!a.error.isEmpty())
                    setLastError(a.error);
            }
            handOnLane(m_catalogueLane);
        },
        Timeout(kCallBudgetMs));
}

void UniswapUiBackend::quote(QString requestJson)
{
    runQuote(requestJson, true);
}

void UniswapUiBackend::runQuote(const QString &requestJson, bool interactive)
{
    if (requestJson != m_quoteRequest)
        ++m_quoteGen;
    m_quoteRequest = requestJson;
    ScopedState s = scopeSnapshot();
    enterQuoteRequest(s, requestJson);
    if (interactive)
        s.swapError.clear();
    publishScope(s);
    // An incomplete form, or an amount of nothing, is nothing to price and not an error.
    if (!describesASwap(requestJson) || isNothing(requestJson)) {
        setQuoteLoading(false);
        return;
    }

    quint64 slot = 0;
    if (!beginLane(m_quoteLane, &slot)) {
        m_quoteAgainInteractive = m_quoteAgainInteractive || interactive;
        return;
    }
    const quint64 gen = m_dataGen;
    const quint64 qgen = m_quoteGen;
    const QString priced = requestJson;
    // ASYNC: the backend quotes (a Multicall3 batch of tens of quoter calls) and has the sender
    // price the calls, in one allowance, and QML calls this on every keystroke. A form the
    // backend refuses comes back in words, like any other refusal.
    modules().uniswap_backend.quoteAsyncResult(withChain(requestJson, shown().chainId),
        [this, gen, qgen, slot, priced, interactive](logos::AsyncResult<QString> res) {
            m_quoteLane.release(slot);
            if (!m_quoteLane.owns(slot))
                return;
            if (gen == m_dataGen && qgen == m_quoteGen) {
                ScopedState st = scopeSnapshot();
                applyQuote(st, res.ok() ? res.value : failure(QStringLiteral("the swap backend did not answer")),
                           priced, interactive);
                publishScope(st);
            }
            handOnLane(m_quoteLane);
        },
        Timeout(kSwapCallBudgetMs));
}

void UniswapUiBackend::setQuoteAutoRefresh(bool on)
{
    ScopedState s = scopeSnapshot();
    if (!on) {
        m_quotePoll.stop();
        ++m_quoteGen;
        m_quoteRequest.clear();
        withdrawQuote(s);
        publishScope(s);
        return;
    }
    s.swapError.clear();
    publishScope(s);
    if (!m_quotePoll.isActive())
        m_quotePoll.start();
}

void UniswapUiBackend::setSettings(QString settingsJson)
{
    const QJsonObject o = parseObject(settingsJson);
    QJsonObject next = m_settings;
    if (o.contains(QStringLiteral("slippageBps"))) {
        const int bps = o.value(QStringLiteral("slippageBps")).toInt(-1);
        if (bps < 0 || bps > 5000) {
            surfaceSwapError(QStringLiteral("slippage must be between 0 and 5000 basis points"));
            return;
        }
        next.insert(QStringLiteral("slippageBps"), bps);
    }
    if (o.contains(QStringLiteral("autoSlippage")))
        next.insert(QStringLiteral("autoSlippage"), o.value(QStringLiteral("autoSlippage")).toBool());
    if (o.contains(QStringLiteral("deadlineMins"))) {
        const int mins = o.value(QStringLiteral("deadlineMins")).toInt(-1);
        if (mins < 1 || mins > 4320) {
            surfaceSwapError(QStringLiteral("the deadline must be between 1 minute and 3 days"));
            return;
        }
        next.insert(QStringLiteral("deadlineMins"), mins);
    }
    m_settings = next;
    setSettingsJson(toJson(m_settings));
}

void UniswapUiBackend::submitSwap(QString requestJson)
{
    ScopedState s = scopeSnapshot();
    s.swapError.clear();
    publishScope(s);
    quint64 slot = 0;
    if (!beginClaim(m_submitInFlight, &slot, [this](bool on) {
            // The claim lapsing with the submit still open is a submit nobody answered, and
            // the view is waiting on either a request id or an error.
            if (!on && m_submitting) {
                m_submitting = false;
                surfaceSwapError(QStringLiteral("the swap was not submitted: no answer"));
            }
        }, kSwapClaimBudgetMs))
        return;
    m_submitting = true;
    const quint64 gen = m_dataGen;
    // The backend builds the swap afresh (the figures on screen may be a block old, and the
    // minimum and the deadline are set from this build) and asks the sender to make it.
    modules().uniswap_backend.swapAsyncResult(withChain(requestJson, shown().chainId),
        [this, gen, slot](logos::AsyncResult<QString> sent) {
            m_submitInFlight.release(slot);
            m_submitting = false;
            if (!m_submitInFlight.isCurrent(slot))
                return;
            ScopedState after = scopeSnapshot();
            const SendApplied a = applySend(after,
                sent.ok() ? sent.value : failure(QStringLiteral("the swap backend did not answer")),
                selectionHeld(gen));
            publishScope(after);
            if (!a.accepted)
                return;
            setLastSwapOutcomeJson(QString());
            setPendingApprovalHandle(a.handle);
            setPendingRequestId(a.requestId);
            m_sendPoll.start();
        },
        Timeout(kSwapCallBudgetMs));
}

void UniswapUiBackend::pollSwap()
{
    if (pendingRequestId().isEmpty()) {
        m_sendPoll.stop();
        return;
    }
    quint64 slot = 0;
    if (!beginClaim(m_pollInFlight, &slot, [this](bool on) { setSwapPolling(on); }))
        return;
    const QString id = pendingRequestId();
    // ASYNC: `send_status` IS the broadcast — the first poll after the approval collects the
    // signatures and sends every leg, which is seconds on a real node.
    modules().uniswap_backend.swap_statusAsyncResult(id,
        [this, slot, id](logos::AsyncResult<QString> res) {
            m_pollInFlight.release(slot);
            if (!m_pollInFlight.isCurrent(slot))
                return;
            setSwapPolling(false);
            if (id != pendingRequestId())
                return;
            const QString reply = res.ok() ? res.value : QString();
            // Silence is not an outcome, and neither is anything the backend calls not final:
            // a send still moving, or a refusal that left it untouched. The next tick asks again.
            if (reply.isEmpty() || !parseObject(reply).value(QStringLiteral("final")).toBool())
                return;
            if (failed(reply, QStringLiteral("swap"))) {
                m_sendPoll.stop();
                setPendingApprovalHandle(QString());
                setPendingRequestId(QString());
                return;
            }
            const QJsonObject settled = parseObject(reply);
            const QString status = settled.value(QStringLiteral("status")).toString();

            m_sendPoll.stop();
            QJsonObject outcome{{QStringLiteral("status"), status}};
            for (const auto &key : {QStringLiteral("hash"), QStringLiteral("reason")}) {
                const QString v = settled.value(key).toString();
                if (!v.isEmpty())
                    outcome.insert(key, v);
            }
            outcome.insert(QStringLiteral("hashes"), settled.value(QStringLiteral("hashes")).toArray());
            // Published BEFORE the pending id clears, so the waiting dialog is never
            // replaced by nothing.
            setLastSwapOutcomeJson(toJson(outcome));
            setPendingApprovalHandle(QString());
            setPendingRequestId(QString());
            refresh();
            const QString reason = settled.value(QStringLiteral("reason")).toString();
            if (status != QLatin1String("broadcast") && !reason.isEmpty())
                setLastError(QStringLiteral("swap %1: %2").arg(status, reason));
        },
        Timeout(kCallBudgetMs));
}

void UniswapUiBackend::cancelSwap()
{
    if (pendingRequestId().isEmpty())
        return;
    modules().uniswap_backend.cancel_swap(pendingRequestId());
    m_sendPoll.stop();
    setLastSwapOutcomeJson(QStringLiteral("{\"status\":\"cancelled\"}"));
    setPendingApprovalHandle(QString());
    setPendingRequestId(QString());
}

void UniswapUiBackend::pollVerifiedProxy()
{
    if (m_vpInFlight.busy())
        applyVerifiedProxy(QString());
    else
        refreshVerifiedProxy();
}

void UniswapUiBackend::refreshVerifiedProxy()
{
    quint64 slot = 0;
    if (!m_vpInFlight.take(kOneCallBudgetMs, &slot))
        return;
    if (shown().chainId == 0) {
        m_vpInFlight.release(slot);
        applyVerifiedProxy(QString());
        return;
    }
    modules().uniswap_backend.verdictAsyncResult(shown().chainId,
        [this, slot](logos::AsyncResult<QString> verdict) {
            m_vpInFlight.release(slot);
            applyVerifiedProxy(verdict.ok() ? verdict.value : QString());
        },
        Timeout(kCallBudgetMs));
}

void UniswapUiBackend::refreshPending()
{
    // Reading the swaps sweeps the receipts that are due first.
    loadBalancesAndSwaps();
}
