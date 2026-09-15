#pragma once

#include <QString>

// Token amounts, as strings of decimal digits. A swap moves base units, a human types token
// units, and the shift between them is exact integer work — never a double, which cannot
// hold 18 decimal places. Every function here is pure and runs in doctests/test_units.cpp.

/// "1.5" with 6 decimals → "1500000". Empty when the text is not an amount: not digits, more
/// fractional places than the token has, or nothing at all. "0" is a valid amount of nothing.
inline QString toBaseUnits(const QString &units, int decimals)
{
    const QString t = units.trimmed();
    if (t.isEmpty() || decimals < 0 || decimals > 77)
        return {};
    const int dot = t.indexOf(QLatin1Char('.'));
    const QString whole = dot < 0 ? t : t.left(dot);
    const QString frac = dot < 0 ? QString() : t.mid(dot + 1);
    if (whole.isEmpty() && frac.isEmpty())
        return {};
    for (const QChar c : whole + frac)
        if (c < QLatin1Char('0') || c > QLatin1Char('9'))
            return {};
    if (frac.size() > decimals)
        return {};
    QString digits = whole + frac + QString(decimals - frac.size(), QLatin1Char('0'));
    int lead = 0;
    while (lead < digits.size() - 1 && digits.at(lead) == QLatin1Char('0'))
        ++lead;
    return digits.mid(lead);
}

/// Every digit of a base-unit amount in token units, with no trailing zeros: "1500000" at 6
/// decimals → "1.5"; "1" at 18 → "0.000000000000000001". Empty for a string that is not digits.
inline QString fromBaseUnitsExact(const QString &base, int decimals)
{
    const QString t = base.trimmed();
    if (t.isEmpty() || decimals < 0)
        return {};
    for (const QChar c : t)
        if (c < QLatin1Char('0') || c > QLatin1Char('9'))
            return {};
    QString digits = t;
    if (digits.size() <= decimals)
        digits = QString(decimals - digits.size() + 1, QLatin1Char('0')) + digits;
    const QString whole = digits.left(digits.size() - decimals);
    QString frac = digits.mid(digits.size() - decimals);
    while (frac.endsWith(QLatin1Char('0')))
        frac.chop(1);
    return frac.isEmpty() ? whole : whole + QLatin1Char('.') + frac;
}

/// A bounded display: at most `places` fractional digits, TRUNCATED rather than rounded so a
/// figure never reads as more than it is, and "<0.00001" for an amount that is not nothing but
/// would print as if it were. Empty for a string that is not digits.
inline QString fromBaseUnits(const QString &base, int decimals, int places = 5)
{
    const QString exact = fromBaseUnitsExact(base, decimals);
    if (exact.isEmpty())
        return {};
    const int dot = exact.indexOf(QLatin1Char('.'));
    if (dot < 0 || exact.size() - dot - 1 <= places)
        return exact;
    QString cut = exact.left(dot + 1 + places);
    while (cut.endsWith(QLatin1Char('0')))
        cut.chop(1);
    if (cut.endsWith(QLatin1Char('.')))
        cut.chop(1);
    if (cut == QLatin1String("0"))
        return QStringLiteral("<0.") + QString(places - 1, QLatin1Char('0')) + QLatin1Char('1');
    return cut;
}

/// Numeric order of two base-unit amounts: -1, 0, 1. Anything that is not digits sorts as
/// unknown and compares equal to nothing — the caller must check the inputs first.
inline int compareBase(const QString &a, const QString &b)
{
    auto strip = [](const QString &s) {
        int lead = 0;
        while (lead < s.size() - 1 && s.at(lead) == QLatin1Char('0'))
            ++lead;
        return s.mid(lead);
    };
    const QString x = strip(a.trimmed()), y = strip(b.trimmed());
    if (x.size() != y.size())
        return x.size() < y.size() ? -1 : 1;
    const int c = x.compare(y);
    return c < 0 ? -1 : c > 0 ? 1 : 0;
}

inline bool isDigits(const QString &s)
{
    if (s.isEmpty())
        return false;
    for (const QChar c : s)
        if (c < QLatin1Char('0') || c > QLatin1Char('9'))
            return false;
    return true;
}

/// How many of `unitOut` one `unitIn` buys, for the rate line: `out / in` in token units, to
/// six significant digits. A display of a ratio, not an amount that moves — the one place a
/// double is allowed, and it is said so here.
inline QString rateOf(const QString &amountInBase, int decimalsIn, const QString &amountOutBase,
                      int decimalsOut)
{
    if (!isDigits(amountInBase) || !isDigits(amountOutBase))
        return {};
    const double in = fromBaseUnitsExact(amountInBase, decimalsIn).toDouble();
    const double out = fromBaseUnitsExact(amountOutBase, decimalsOut).toDouble();
    if (!(in > 0.0) || !(out > 0.0))
        return {};
    const double r = out / in;
    QString s = QString::number(r, 'g', 6);
    if (s.contains(QLatin1Char('e')))
        s = QString::number(r, 'f', 12);
    if (s.contains(QLatin1Char('.'))) {
        while (s.endsWith(QLatin1Char('0')))
            s.chop(1);
        if (s.endsWith(QLatin1Char('.')))
            s.chop(1);
    }
    return s;
}
