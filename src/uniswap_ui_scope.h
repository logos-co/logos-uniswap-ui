#pragma once

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

inline QJsonObject parseObject(const QString &reply)
{
    return QJsonDocument::fromJson(reply.toUtf8()).object();
}

inline QString toJson(const QJsonObject &o)
{
    return QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Compact));
}

inline QString toJson(const QJsonArray &a)
{
    return QString::fromUtf8(QJsonDocument(a).toJson(QJsonDocument::Compact));
}

inline bool replyOk(const QString &reply)
{
    return parseObject(reply).value(QStringLiteral("ok")).toBool();
}

/// A refusal, worded by the module that refused. The rule that produced it lives there.
inline QString replyError(const QString &reply)
{
    const QString e = parseObject(reply).value(QStringLiteral("error")).toString();
    return e.isEmpty() ? QStringLiteral("the request was refused") : e;
}

inline QString refusal(const QString &reply, const QString &context)
{
    return context.isEmpty() ? replyError(reply)
                             : QStringLiteral("%1: %2").arg(context, replyError(reply));
}

/// Re-serialize one member of a reply, so the view receives just the payload.
inline QString member(const QString &reply, const char *key)
{
    const QJsonValue v = parseObject(reply).value(QLatin1String(key));
    if (v.isArray())
        return toJson(v.toArray());
    if (v.isObject())
        return toJson(v.toObject());
    return {};
}

/// The account and network every scoped value on screen was read under. chainId 0 means the
/// active network could not be read.
struct Selection {
    QString account;
    int chainId = 0;

    bool operator==(const Selection &o) const
    {
        return chainId == o.chainId && account.compare(o.account, Qt::CaseInsensitive) == 0;
    }
};

inline Selection selectionOf(const QString &account, const QString &networkJson)
{
    Selection s;
    s.account = account;
    s.chainId = parseObject(networkJson).value(QStringLiteral("chainId")).toInt();
    return s;
}

/// The scope a REPLY says it answered for — the half a generation counter cannot know.
struct ReplyScope {
    bool namesChain = false;
    bool namesAccount = false;
    int chainId = 0;
    QString account;

    bool names() const { return namesChain || namesAccount; }
    bool agreesWith(const Selection &s) const
    {
        return (!namesChain || chainId == s.chainId)
            && (!namesAccount || account.compare(s.account, Qt::CaseInsensitive) == 0);
    }
};

/// The wallet's reads name their account `address`; a sender quote calls it `from`; a swap
/// quote calls it `owner`.
inline ReplyScope replyScope(const QJsonObject &o)
{
    ReplyScope r;
    const QJsonValue chain = o.value(QStringLiteral("chainId"));
    if (chain.isDouble()) {
        r.namesChain = true;
        r.chainId = chain.toInt();
    }
    for (const char *key : {"address", "from", "owner"}) {
        const QJsonValue who = o.value(QLatin1String(key));
        if (who.isString()) {
            r.namesAccount = true;
            r.account = who.toString();
            break;
        }
    }
    return r;
}

/// May this reply be acted on for the selection on screen? One naming another account or
/// chain is about something else; a successful payload naming neither cannot be attributed
/// and is refused too; a refusal names nothing by design and is this call's own answer.
inline bool answersFor(const QString &reply, const Selection &shown)
{
    const QJsonObject o = parseObject(reply);
    const ReplyScope r = replyScope(o);
    if (!r.agreesWith(shown))
        return false;
    return r.names() || !o.value(QStringLiteral("ok")).toBool();
}

/// Case-folded equality with an absent value on EITHER side matching NOTHING.
inline bool sameHexValue(const QString &a, const QString &b)
{
    return !a.isEmpty() && !b.isEmpty() && a.compare(b, Qt::CaseInsensitive) == 0;
}

/// Whether a request describes a swap at all: two different tokens and an amount. An
/// incomplete form is nothing to price rather than an error.
inline bool describesASwap(const QString &requestJson)
{
    const QJsonObject r = parseObject(requestJson);
    const QString in = r.value(QStringLiteral("tokenIn")).toString().trimmed();
    const QString out = r.value(QStringLiteral("tokenOut")).toString().trimmed();
    const QString amount = r.value(QStringLiteral("amountUnits")).toString().trimmed();
    return !in.isEmpty() && !out.isEmpty() && !amount.isEmpty()
        && in.compare(out, Qt::CaseInsensitive) != 0;
}

/// Every published value that means something only against a particular selection. This
/// list IS the rule: a property that belongs here and is not listed is one free to outlive
/// the account or network it describes.
struct ScopedState {
    Selection at;
    bool fresh = false;

    // account × chain
    QString balances;
    QString balancesRoute;
    QString quote = QStringLiteral("{}");
    QString quoteRequest;
    bool quoteStale = false;
    QString swapError;
    QString swaps;

    // chain only
    QString tokens;
    QString catalogue;
    QString feeTiers = QStringLiteral("{}");
    QString verifiedProxy = QStringLiteral("{}");
};

inline void withdrawQuote(ScopedState &s)
{
    s.quote = QStringLiteral("{}");
    s.quoteRequest.clear();
    s.quoteStale = false;
}

/// Move the quote to a new request, withdrawing figures priced for the one it replaces.
inline bool enterQuoteRequest(ScopedState &s, const QString &request)
{
    if (s.quoteRequest == request)
        return false;
    withdrawQuote(s);
    return true;
}

/// Move the selection, withdrawing everything that no longer describes it. Empty is UNKNOWN
/// throughout. Returns true when the selection actually moved.
inline bool enterScope(ScopedState &s, const Selection &to)
{
    if (s.at == to)
        return false;
    const bool chainMoved = s.at.chainId != to.chainId;
    s.at = to;
    s.fresh = false;
    s.balances.clear();
    s.balancesRoute.clear();
    s.swaps.clear();
    withdrawQuote(s);
    s.swapError.clear();
    if (chainMoved) {
        s.tokens.clear();
        s.catalogue.clear();
        s.feeTiers = QStringLiteral("{}");
        s.verifiedProxy = QStringLiteral("{}");
    }
    return true;
}
