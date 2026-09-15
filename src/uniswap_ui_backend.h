#pragma once

#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>

#include "uniswap_ui_apply.h"
#include "uniswap_ui_guard.h"
#include "uniswap_ui_scope.h"
#include "rep_uniswap_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Uniswap app's backend.
//
// Every module call is made here over the generated typed clients; the QML half renders and
// makes no module calls of its own. Nothing on this class takes or returns key material: it
// asks uniswap_module for a quote and the calls that make it, asks tx_sender_module to send
// them, and composes chain, asset, account, and fee reads directly. It never broadcasts: the
// sender does, once the keystore has a human's yes.
//
// It holds no rule about what may reach the screen. Every scoped value is produced by a pure
// transition in uniswap_ui_apply.h and published through publishScope() below, so the guard
// deciding whether a reply is rendered is executed by doctests/test_apply.cpp rather than
// described by a grep over this file.
class UniswapUiBackend : public UniswapUiSimpleSource,
                         public LogosUiPluginContext
{
public:
    UniswapUiBackend();

    void refresh() override;
    void selectAccount(QString address) override;
    void selectNetwork(int chainId) override;
    void searchTokens(QString query) override;
    void loadMoreCatalogue() override;
    void quote(QString requestJson) override;
    void setQuoteAutoRefresh(bool on) override;
    void setSettings(QString settingsJson) override;
    void submitSwap(QString requestJson) override;
    void pollSwap() override;
    void cancelSwap() override;
    void refreshSwaps() override;
    void refreshPending() override;

    /// The two halves of the selection, overridden onto publishSelection() below, so a
    /// handler that publishes an account or a network gets the withdrawal whether it asked
    /// for it or not.
    void setSelectedAccount(QString address) override;
    void setActiveNetworkJson(QString networkJson) override;

protected:
    void onContextReady() override;

private:
    void publishSelection(const QString &account, const QString &networkJson);
    ScopedState scopeSnapshot() const;
    /// The ONLY writer of a scoped property.
    void publishScope(const ScopedState &s);
    Selection shown() const;
    bool selectionHeld(quint64 gen) const { return gen == m_dataGen; }
    bool adoptChain(int chainId);

    bool beginLane(AsyncLane &lane, quint64 *slot);
    void handOnLane(AsyncLane &lane);
    bool beginClaim(InFlight &claim, quint64 *slot, const SetLoading &setLoading);

    void loadNetwork();
    void loadAccounts();
    /// Balances then this app's swaps, asynchronously: both reach eth_rpc's verified gate.
    void loadBalancesAndSwaps();
    void loadFeeTiers();
    /// One quote: uniswap_module builds the swap, tx_sender_module prices it. Two async legs
    /// on one lane, so a keystroke landing mid-call is priced after it, never beside it.
    void runQuote(const QString &requestJson, bool interactive);
    void runCatalogueSearch();
    void applyVerifiedProxy(const QString &verdictJson);
    void pollVerifiedProxy();
    void refreshVerifiedProxy();
    void setSweep(bool due);
    /// Surface a refusal verbatim on this app's own error line.
    bool failed(const QString &reply, const QString &context);
    void refreshSoon();
    void surfaceSwapError(const QString &error);

    bool m_inFlight = false;
    bool m_networkRetry = false;
    bool m_refreshAgain = false;
    QTimer m_sendPoll;
    QTimer m_pendingPoll;
    QTimer m_vpPoll;
    QTimer m_quotePoll;
    InFlight m_vpInFlight;
    int m_vpSilent = 0;

    AsyncLane m_dataLane;
    AsyncLane m_quoteLane;
    AsyncLane m_catalogueLane;
    InFlight m_pendingInFlight;
    InFlight m_feesInFlight;
    /// One poll of the swap awaiting approval at a time: `send_status` IS the broadcast.
    InFlight m_pollInFlight;
    /// One submit at a time. The button is disabled while it is held.
    InFlight m_submitInFlight;
    bool m_submitting = false;
    bool m_quoteAgainInteractive = false;
    QString m_quoteRequest;
    QString m_catalogueQuery;
    int m_catalogueChain = 0;
    /// The first row the next call asks for: 0 for a new question, the rows held for its next page.
    int m_catalogueOffset = 0;
    QJsonObject m_settings;
    quint64 m_dataGen = 0;
    quint64 m_quoteGen = 0;
};
