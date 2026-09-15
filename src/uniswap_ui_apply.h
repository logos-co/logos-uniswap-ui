#pragma once

#include <algorithm>

#include "uniswap_ui_scope.h"
#include "uniswap_ui_units.h"

// Every guard deciding whether a reply reaches the screen lives here, INSIDE the transition it
// guards, as a pure function over ScopedState. The backend snapshots, calls one of these, and
// publishes: it holds no rule of its own. doctests/test_apply.cpp is the table that runs them.

struct Applied {
    bool acted = false;
    QString error;
};

/// The verdict to publish once the wallet backend has stopped answering. Unknown is not
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

/// The wallet's token list for the chain. Unknown, not the previous network's, on a failure.
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

/// The status of a bundle from the status of its legs. The worst leg wins: a swap whose
/// approval landed and whose swap reverted is a failed swap, not a half-confirmed one.
inline QString bundleStatus(const QJsonArray &legs)
{
    bool failed = false, pending = false, stalled = false, blocked = false;
    for (const QJsonValue &v : legs) {
        const QJsonObject r = v.toObject();
        const QString st = r.value(QStringLiteral("status")).toString();
        if (st == QLatin1String("failed"))
            failed = true;
        else if (st != QLatin1String("confirmed"))
            pending = true;
        if (r.value(QStringLiteral("stalled")).toBool())
            stalled = true;
        if (r.value(QStringLiteral("verificationBlocked")).toBool())
            blocked = true;
    }
    if (failed)
        return QStringLiteral("failed");
    if (blocked)
        return QStringLiteral("blocked");
    if (stalled)
        return QStringLiteral("stalled");
    return pending ? QStringLiteral("pending") : QStringLiteral("confirmed");
}

/// This app's swaps out of the sender's rows: the rows it tagged, grouped by bundle. The tag
/// is the app's own (`meta.app`), which is enough to find its rows in a list it shares with
/// the wallet; who really asked is the sender's `origin`, and the rows carry that too.
inline QJsonArray groupSwaps(const QJsonArray &rows, const QString &app)
{
    QList<QJsonObject> groups;
    for (const QJsonValue &v : rows) {
        const QJsonObject r = v.toObject();
        if (r.value(QStringLiteral("meta")).toObject().value(QStringLiteral("app")).toString() != app)
            continue;
        QString id = r.value(QStringLiteral("requestId")).toString();
        if (id.isEmpty())
            id = r.value(QStringLiteral("hash")).toString();
        auto it = std::find_if(groups.begin(), groups.end(), [&](const QJsonObject &g) {
            return g.value(QStringLiteral("requestId")).toString() == id;
        });
        if (it == groups.end()) {
            groups.append(QJsonObject{{QStringLiteral("requestId"), id},
                                      {QStringLiteral("legs"), QJsonArray{}}});
            it = groups.end() - 1;
        }
        QJsonArray legs = it->value(QStringLiteral("legs")).toArray();
        legs.append(r);
        it->insert(QStringLiteral("legs"), legs);
    }
    QList<QJsonObject> finished;
    for (QJsonObject g : groups) {
        QList<QJsonObject> ordered;
        for (const QJsonValue &v : g.value(QStringLiteral("legs")).toArray())
            ordered.append(v.toObject());
        std::stable_sort(ordered.begin(), ordered.end(), [](const QJsonObject &a, const QJsonObject &b) {
            return a.value(QStringLiteral("leg")).toInt() < b.value(QStringLiteral("leg")).toInt();
        });
        QJsonArray legs, hashes;
        QJsonObject swapMeta;
        QString label;
        double newest = 0;
        for (const QJsonObject &r : ordered) {
            legs.append(r);
            const QString h = r.value(QStringLiteral("hash")).toString();
            if (!h.isEmpty())
                hashes.append(h);
            const QJsonObject meta = r.value(QStringLiteral("meta")).toObject();
            if (meta.value(QStringLiteral("kind")).toString() == QLatin1String("swap") || swapMeta.isEmpty()) {
                swapMeta = meta;
                label = r.value(QStringLiteral("label")).toString();
            }
            newest = std::max(newest, r.value(QStringLiteral("timestamp")).toDouble());
        }
        g.insert(QStringLiteral("legs"), legs);
        g.insert(QStringLiteral("hashes"), hashes);
        g.insert(QStringLiteral("swap"), swapMeta);
        g.insert(QStringLiteral("label"), label);
        g.insert(QStringLiteral("timestamp"), newest);
        g.insert(QStringLiteral("status"), bundleStatus(legs));
        g.insert(QStringLiteral("origin"), ordered.isEmpty()
                     ? QString() : ordered.first().value(QStringLiteral("origin")).toString());
        finished.append(g);
    }
    // Newest first, as the wallet's Activity is.
    std::stable_sort(finished.begin(), finished.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value(QStringLiteral("timestamp")).toDouble() > b.value(QStringLiteral("timestamp")).toDouble();
    });
    QJsonArray result;
    for (const QJsonObject &g : finished)
        result.append(g);
    return result;
}

/// What a history reply says about the receipt sweep. A read that failed says nothing.
enum class SweepVerdict { Unchanged, Stop, Run };

struct SwapsApplied {
    bool acted = false;
    SweepVerdict sweep = SweepVerdict::Unchanged;
};

/// This app's swaps, from the sender's history reply for the selected account and chain.
inline SwapsApplied applySwaps(ScopedState &s, const QString &reply, const QString &app)
{
    if (!answersFor(reply, s.at))
        return {};
    const QJsonObject h = parseObject(reply);
    if (!h.value(QStringLiteral("ok")).toBool()) {
        s.swaps.clear();
        return {true, SweepVerdict::Unchanged};
    }
    s.swaps = toJson(groupSwaps(h.value(QStringLiteral("transactions")).toArray(), app));
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
        publish = unknownVerdict(s.at.chainId, QStringLiteral("the wallet backend stopped answering"));
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

enum class NetworkStep { AskAgain, Publish, Unknown };

inline NetworkStep networkStep(bool selectionHeld, const QString &reply)
{
    if (!selectionHeld)
        return NetworkStep::AskAgain;
    return replyOk(reply) ? NetworkStep::Publish : NetworkStep::Unknown;
}

inline bool mayAdopt(bool selectionHeld, int reportedChainId)
{
    return selectionHeld && reportedChainId != 0;
}

// ── the swap request, from the form to the two modules ─────────────────────────────

/// The form's request, parsed. Amounts arrive in token units and leave in base units.
struct SwapForm {
    QString from;
    QString tokenIn;
    QString tokenOut;
    QString symbolIn;
    QString symbolOut;
    int decimalsIn = 18;
    int decimalsOut = 18;
    QString amountUnits;
    QString amountIn;
    QString tier = QStringLiteral("normal");
    int slippageBps = 50;
    int deadlineMins = 30;
    QString recipient;
};

/// Empty error on success. A form that is not an amount is refused HERE, in words the user
/// can act on, rather than sent on as zero.
inline QString parseSwapForm(const QString &requestJson, SwapForm *out)
{
    const QJsonObject r = parseObject(requestJson);
    out->from = r.value(QStringLiteral("from")).toString();
    out->tokenIn = r.value(QStringLiteral("tokenIn")).toString().trimmed();
    out->tokenOut = r.value(QStringLiteral("tokenOut")).toString().trimmed();
    out->symbolIn = r.value(QStringLiteral("symbolIn")).toString();
    out->symbolOut = r.value(QStringLiteral("symbolOut")).toString();
    out->decimalsIn = r.value(QStringLiteral("decimalsIn")).toInt(18);
    out->decimalsOut = r.value(QStringLiteral("decimalsOut")).toInt(18);
    out->amountUnits = r.value(QStringLiteral("amountUnits")).toString().trimmed();
    out->tier = r.value(QStringLiteral("tier")).toString(QStringLiteral("normal"));
    out->slippageBps = r.value(QStringLiteral("slippageBps")).toInt(50);
    out->deadlineMins = r.value(QStringLiteral("deadlineMins")).toInt(30);
    out->recipient = r.value(QStringLiteral("recipient")).toString().trimmed();
    if (out->from.isEmpty())
        return QStringLiteral("no account is selected");
    out->amountIn = toBaseUnits(out->amountUnits, out->decimalsIn);
    if (out->amountIn.isEmpty())
        return QStringLiteral("the amount must be a number with at most %1 decimal places")
            .arg(out->decimalsIn);
    if (out->slippageBps < 0 || out->slippageBps > 5000)
        return QStringLiteral("slippage must be between 0 and 5000 basis points");
    return {};
}

/// What uniswap_module is asked. `owner` makes the batch read the balance and allowance.
inline QString swapModuleRequest(const SwapForm &f, qint64 deadlineUnix)
{
    QJsonObject o{
        {QStringLiteral("tokenIn"), f.tokenIn},
        {QStringLiteral("tokenOut"), f.tokenOut},
        {QStringLiteral("amountIn"), f.amountIn},
        {QStringLiteral("owner"), f.from},
        {QStringLiteral("symbolIn"), f.symbolIn},
        {QStringLiteral("symbolOut"), f.symbolOut},
        {QStringLiteral("slippageBps"), f.slippageBps},
    };
    if (!f.recipient.isEmpty())
        o.insert(QStringLiteral("recipient"), f.recipient);
    if (deadlineUnix > 0)
        o.insert(QStringLiteral("deadline"), static_cast<double>(deadlineUnix));
    return toJson(o);
}

/// The sender's request for a built swap. No leg carries a gas limit: `fee_module` estimates
/// the swap behind its approval with that allowance applied, and a limit this app invented
/// would only stand in the way of a real one.
inline QString senderRequest(const QJsonObject &built, const SwapForm &f, const QString &app,
                             const QString &purpose, int chainId)
{
    QJsonArray calls;
    const QJsonObject route = built.value(QStringLiteral("route")).toObject();
    for (const QJsonValue &v : built.value(QStringLiteral("calls")).toArray()) {
        const QJsonObject c = v.toObject();
        const QString kind = c.value(QStringLiteral("kind")).toString();
        QJsonObject meta{
            {QStringLiteral("app"), app},
            {QStringLiteral("kind"), kind},
            {QStringLiteral("tokenIn"), f.tokenIn},
            {QStringLiteral("tokenOut"), f.tokenOut},
            {QStringLiteral("symbolIn"), f.symbolIn},
            {QStringLiteral("symbolOut"), f.symbolOut},
            {QStringLiteral("decimalsIn"), f.decimalsIn},
            {QStringLiteral("decimalsOut"), f.decimalsOut},
            {QStringLiteral("amountIn"), f.amountIn},
            {QStringLiteral("amountOut"), built.value(QStringLiteral("amountOut")).toString()},
            {QStringLiteral("amountOutMin"), built.value(QStringLiteral("amountOutMin")).toString()},
            {QStringLiteral("route"), route},
        };
        QJsonObject call{
            {QStringLiteral("to"), c.value(QStringLiteral("to")).toString()},
            {QStringLiteral("value"), c.value(QStringLiteral("value")).toString()},
            {QStringLiteral("data"), c.value(QStringLiteral("data")).toString()},
            {QStringLiteral("label"), c.value(QStringLiteral("label")).toString()},
            {QStringLiteral("meta"), meta},
        };
        calls.append(call);
    }
    QJsonObject o{
        {QStringLiteral("chainId"), chainId},
        {QStringLiteral("from"), f.from},
        {QStringLiteral("purpose"), purpose},
        {QStringLiteral("calls"), calls},
        {QStringLiteral("tier"), f.tier},
    };
    return toJson(o);
}

/// The sentence the keystore shows the human, and the sender records: what leaves, what at
/// least comes back, and where. Every digit: it is a claim the human is asked to approve,
/// and "<0.00001" is not a claim.
inline QString swapPurpose(const SwapForm &f, const QJsonObject &built)
{
    const QString in = fromBaseUnitsExact(f.amountIn, f.decimalsIn);
    const QString minOut = fromBaseUnitsExact(built.value(QStringLiteral("amountOutMin")).toString(), f.decimalsOut);
    return QStringLiteral("Swap %1 %2 for at least %3 %4 on Uniswap")
        .arg(in, f.symbolIn.isEmpty() ? f.tokenIn : f.symbolIn, minOut,
             f.symbolOut.isEmpty() ? f.tokenOut : f.symbolOut);
}

/// The quote the view renders: the built swap, the sender's pricing of it under `fee`, and
/// the display strings the view would otherwise have to derive from base units. `from` is
/// stamped so the reply names the account it is about, as every scoped reply must.
inline QString mergedQuote(const QJsonObject &built, const QString &feeReply, const SwapForm &f)
{
    QJsonObject q = built;
    q.insert(QStringLiteral("from"), f.from);
    q.insert(QStringLiteral("amountInDisplay"), fromBaseUnits(f.amountIn, f.decimalsIn));
    const QString out = built.value(QStringLiteral("amountOut")).toString();
    const QString minOut = built.value(QStringLiteral("amountOutMin")).toString();
    q.insert(QStringLiteral("amountOutDisplay"), fromBaseUnits(out, f.decimalsOut));
    q.insert(QStringLiteral("amountOutExact"), fromBaseUnitsExact(out, f.decimalsOut));
    q.insert(QStringLiteral("amountOutMinDisplay"), fromBaseUnits(minOut, f.decimalsOut));
    q.insert(QStringLiteral("amountOutMinExact"), fromBaseUnitsExact(minOut, f.decimalsOut));
    q.insert(QStringLiteral("rate"), rateOf(f.amountIn, f.decimalsIn, out, f.decimalsOut));
    q.insert(QStringLiteral("rateInverse"), rateOf(out, f.decimalsOut, f.amountIn, f.decimalsIn));
    const QString balance = built.value(QStringLiteral("balanceIn")).toString();
    if (isDigits(balance)) {
        q.insert(QStringLiteral("balanceInDisplay"), fromBaseUnits(balance, f.decimalsIn));
        q.insert(QStringLiteral("insufficientBalance"), compareBase(balance, f.amountIn) < 0);
    }
    const QJsonObject fee = parseObject(feeReply);
    if (fee.isEmpty())
        q.insert(QStringLiteral("fee"), QJsonObject{{QStringLiteral("ok"), false},
                                                    {QStringLiteral("error"), QStringLiteral("the sender did not answer")}});
    else
        q.insert(QStringLiteral("fee"), fee);
    return toJson(q);
}
