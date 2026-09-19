#pragma once

#include <algorithm>

#include "uniswap_ui_scope.h"

// Every guard deciding whether a reply reaches the screen lives here, INSIDE the transition it
// guards, as a pure function over ScopedState. The backend snapshots, calls one of these, and
// publishes: it holds no rule of its own. doctests/test_apply.cpp is the table that runs them.

struct Applied {
    bool acted = false;
    QString error;
};

/// The verdict to publish once uniswap_backend has stopped answering. Unknown is not
/// "off": it blocks.
inline QString unknownVerdict(int chainId, const QString &why)
{
    const QJsonObject v{
        {QStringLiteral("ok"), false},
        {QStringLiteral("error"), why},
        {QStringLiteral("chainId"), chainId},
        {QStringLiteral("mode"), QStringLiteral("unknown")},
        {QStringLiteral("state"), QStringLiteral("unhealthy")},
        {QStringLiteral("usable"), false},
        {QStringLiteral("blocking"), true},
        {QStringLiteral("message"), QStringLiteral("The verified-proxy state could not be read.")},
        {QStringLiteral("action"), QStringLiteral("restart_or_reload")},
        {QStringLiteral("detail"), why},
    };
    return toJson(v);
}

/// Balances. A reply naming another selection is about something else and is dropped whole.
inline Applied applyBalances(ScopedState &s, const QString &reply)
{
    if (!answersFor(reply, s.at))
        return {};
    const bool ok = replyOk(reply);
    s.balances = ok ? member(reply, "balances") : QString();
    s.balancesRoute = ok ? parseObject(reply).value(QStringLiteral("route")).toString() : QString();
    s.fresh = true;
    return {true, ok ? QString() : refusal(reply, QStringLiteral("balances"))};
}

/// The tokens offered on the chain. Unknown, not the previous network's, on a failure.
inline Applied applyTokens(ScopedState &s, const QString &reply)
{
    const bool ok = replyOk(reply);
    s.tokens = (ok && answersFor(reply, s.at)) ? member(reply, "tokens") : QString();
    return {ok, ok ? QString() : refusal(reply, QStringLiteral("tokens"))};
}

/// The catalogue, verbatim: it carries `listed`, `total`, `shown` and `listError`, and the
/// picker tells an empty catalogue from one that could not be read by those.
inline Applied applyCatalogue(ScopedState &s, const QString &reply)
{
    if (!answersFor(reply, s.at))
        return {};
    const bool ok = replyOk(reply);
    s.catalogue = ok ? reply : QString();
    return {true, ok ? QString() : refusal(reply, QStringLiteral("token list"))};
}

/// A later page of the catalogue, appended onto the one on screen. It must continue that
/// answer — same chain, its `offset` exactly the rows already held — or nothing moves: a page
/// for the previous query, or one that failed, is not a reason to drop what is shown. The
/// counts follow the page, and `appended` tells the picker to grow rather than start over.
inline Applied applyCataloguePage(ScopedState &s, const QString &reply, int offset)
{
    if (!answersFor(reply, s.at))
        return {};
    if (!replyOk(reply))
        return {true, refusal(reply, QStringLiteral("token list"))};
    QJsonObject acc = parseObject(s.catalogue);
    const QJsonObject page = parseObject(reply);
    QJsonArray rows = acc.value(QStringLiteral("tokens")).toArray();
    if (!acc.value(QStringLiteral("ok")).toBool() || offset <= 0 || offset != rows.size()
        || page.value(QStringLiteral("offset")).toInt(-1) != offset
        || page.value(QStringLiteral("chainId")) != acc.value(QStringLiteral("chainId")))
        return {};
    for (const QJsonValue &v : page.value(QStringLiteral("tokens")).toArray())
        rows.append(v);
    acc.insert(QStringLiteral("tokens"), rows);
    acc.insert(QStringLiteral("shown"), rows.size());
    acc.insert(QStringLiteral("total"), page.value(QStringLiteral("total")));
    acc.insert(QStringLiteral("listed"), page.value(QStringLiteral("listed")));
    acc.insert(QStringLiteral("hasMore"), page.value(QStringLiteral("hasMore")).toBool());
    acc.insert(QStringLiteral("appended"), true);
    s.catalogue = toJson(acc);
    return {true, QString()};
}

inline void applyFeeTiers(ScopedState &s, const QString &reply)
{
    s.feeTiers = (replyOk(reply) && answersFor(reply, s.at)) ? reply : QStringLiteral("{}");
}

/// Nothing to read: the screen showing nothing does describe an empty selection.
inline void applyNoAccount(ScopedState &s)
{
    s.balances.clear();
    s.balancesRoute.clear();
    s.swaps = QStringLiteral("[]");
    s.fresh = true;
}

/// One quote against the request it priced. `interactive` is a user edit, whose failure is
/// the user's to read; a timer tick's failure only marks the figure stale.
inline void applyQuote(ScopedState &s, const QString &reply, const QString &priced, bool interactive)
{
    if (replyOk(reply) && answersFor(reply, s.at)) {
        s.quote = reply;
        s.quoteRequest = priced;
        s.quoteStale = false;
        // A quote that landed answers the refusal before it: a timer tick that succeeds
        // after a keystroke that failed must not leave the failure standing beside it.
        s.swapError.clear();
    } else if (replyOk(reply)) {
        withdrawQuote(s);
    } else if (interactive) {
        withdrawQuote(s);
        s.swapError = replyError(reply);
    } else {
        s.quoteStale = true;
    }
}

/// What a history reply says about the receipt sweep. A read that failed says nothing.
enum class SweepVerdict { Unchanged, Stop, Run };

struct SwapsApplied {
    bool acted = false;
    SweepVerdict sweep = SweepVerdict::Unchanged;
};

/// This app's swaps, grouped by uniswap_backend, for the selected account and chain.
inline SwapsApplied applySwaps(ScopedState &s, const QString &reply)
{
    if (!answersFor(reply, s.at))
        return {};
    const QJsonObject h = parseObject(reply);
    if (!h.value(QStringLiteral("ok")).toBool()) {
        s.swaps.clear();
        return {true, SweepVerdict::Unchanged};
    }
    s.swaps = toJson(h.value(QStringLiteral("swaps")).toArray());
    const bool due = h.value(QStringLiteral("stillDue")).toBool();
    return {true, due ? SweepVerdict::Run : SweepVerdict::Stop};
}

/// What a verified-proxy reply leaves behind: the new silence count, and whether the poll
/// keeps running. One blip keeps the last verdict; a backend answering nothing must not hold
/// "ready" up while nothing is being verified.
struct VerdictApplied {
    int silent = 0;
    bool poll = true;
};

inline VerdictApplied applyVerdict(ScopedState &s, const QString &reply, int silent, int maxSilent)
{
    QString publish = reply;
    if (!parseObject(publish).contains(QStringLiteral("mode")) || !answersFor(publish, s.at)) {
        if (++silent < maxSilent)
            return {silent, true};
        publish = unknownVerdict(s.at.chainId, QStringLiteral("the RPC module stopped answering"));
    } else {
        silent = 0;
    }
    const QJsonObject prev = parseObject(s.verifiedProxy);
    const QJsonObject next = parseObject(publish);
    s.verifiedProxy = publish;
    // A quote priced under the previous verdict is not the one the user would be signing.
    if (prev.value(QStringLiteral("mode")) != next.value(QStringLiteral("mode"))
        || prev.value(QStringLiteral("state")) != next.value(QStringLiteral("state"))) {
        withdrawQuote(s);
        s.balancesRoute.clear();
    }
    return {silent, next.value(QStringLiteral("mode")).toString() != QLatin1String("off")};
}

/// What `send` left behind. The request id is deliberately NOT scoped: it is a request
/// sitting in the signer, and forgetting it would orphan an approval the user still has to
/// answer.
struct SendApplied {
    bool accepted = false;
    QString requestId;
    QString handle;
    bool surfaced = false;
};

inline SendApplied applySend(ScopedState &s, const QString &reply, bool selectionHeld)
{
    if (replyOk(reply)) {
        const QJsonObject o = parseObject(reply);
        return {true, o.value(QStringLiteral("requestId")).toString(),
                o.value(QStringLiteral("handle")).toString(), false};
    }
    if (!selectionHeld)
        return {};
    s.swapError = replyError(reply);
    return {false, QString(), QString(), true};
}

/// Keep the UI-local chain while it is offered. Otherwise prefer the first mainnet, then
/// the first remaining row. The backend relays eth_rpc's mainnet-before-testnet order, but the
/// preference is explicit here so this app remains correct for any provider ordering.
inline int chooseChain(const QJsonArray &chains, int current)
{
    for (const QJsonValue &value : chains) {
        if (value.toObject().value(QStringLiteral("chainId")).toInt() == current)
            return current;
    }
    for (const QJsonValue &value : chains) {
        const QJsonObject row = value.toObject();
        if (!row.value(QStringLiteral("testnet")).toBool())
            return row.value(QStringLiteral("chainId")).toInt();
    }
    return chains.isEmpty() ? 0
                            : chains.first().toObject().value(QStringLiteral("chainId")).toInt();
}

// ── the swap request, as the backend takes it ─────────────────────────────────────

/// The form's request on the chain on screen: the backend reads the form's own fields.
inline QString withChain(const QString &requestJson, int chainId)
{
    QJsonObject o = parseObject(requestJson);
    o.insert(QStringLiteral("chainId"), chainId);
    return toJson(o);
}

/// An amount of nothing ("", "0", "0.00", ".") is nothing to price, and not an error either.
inline bool isNothing(const QString &requestJson)
{
    const QString a = parseObject(requestJson).value(QStringLiteral("amountUnits")).toString().trimmed();
    return std::all_of(a.begin(), a.end(), [](QChar c) { return c == QLatin1Char('0') || c == QLatin1Char('.'); });
}
