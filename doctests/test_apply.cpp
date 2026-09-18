// Every guard that decides whether a reply reaches the screen, and the request this view hands
// its backend, as a table. The transitions live in src/uniswap_ui_apply.h and are
// the only things that write a scoped value; the backend snapshots, calls one, and publishes.
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) test_apply.cpp -o /tmp/t && /tmp/t
#include <cstdio>
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif
#include "uniswap_ui_apply.h"

namespace {
int failures = 0;
const char *ALICE = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

void expect(const char *label, const char *claim, bool got)
{
    if (!got) ++failures;
    std::printf("  %s  %-50s %s\n", got ? "PASS" : "FAIL", label, claim);
}
void same(const char *label, const QString &got, const QString &want)
{
    const bool ok = got == want;
    if (!ok) ++failures;
    std::printf("  %s  %-50s got=%s\n", ok ? "PASS" : "FAIL", label, got.isNull() ? "<unknown>" : got.toUtf8().constData());
}
QString q(const char *s) { return QString::fromUtf8(s); }

ScopedState screen()
{
    ScopedState s;
    s.at = selectionOf(q(ALICE), QStringLiteral(R"({"chainId":11155111})"));
    s.fresh = true;
    s.balances = QStringLiteral(R"([{"symbol":"ETH","display":"1.5"}])");
    s.balancesRoute = QStringLiteral("verified");
    s.swaps = QStringLiteral("[]");
    s.tokens = QStringLiteral(R"([{"symbol":"ETH"}])");
    s.feeTiers = QStringLiteral(R"({"source":"eip1559"})");
    s.verifiedProxy = QStringLiteral(R"({"ok":true,"chainId":11155111,"mode":"required","state":"ready"})");
    return s;
}

} // namespace

int main()
{
    std::printf("networks: the backend's choices, with a UI-local default\n");
    {
        const QJsonArray choices = QJsonDocument::fromJson(R"([
          {"chainId":11155111,"name":"Sepolia","testnet":true},
          {"chainId":1,"name":"Ethereum","testnet":false}
        ])").array();
        expect("the current chain remains this app's choice", "Sepolia", chooseChain(choices, 11155111) == 11155111);
        expect("an unavailable choice falls back to a mainnet", "Ethereum", chooseChain(choices, 99) == 1);
        QJsonArray testnets; testnets.append(choices.first());
        expect("a testnet is still usable when it is all the scope offers", "Sepolia",
               chooseChain(testnets, 99) == 11155111);
        expect("no enabled in-scope chain", "means no selection", chooseChain({}, 1) == 0);
    }

    std::printf("balances: a reply naming another selection is not late, it is about something else\n");
    {
        ScopedState s = screen(); s.fresh = false; s.balances.clear();
        const Applied a = applyBalances(s, q(R"({"ok":true,"chainId":1,"address":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","balances":[{"symbol":"ETH"}],"route":"verified"})"));
        expect("a reply for another chain", "is not acted on", !a.acted);
        expect("...and the freshness stamp", "stays down", !s.fresh);
    }
    {
        ScopedState s = screen(); s.fresh = false;
        const Applied a = applyBalances(s, q(R"({"ok":true,"chainId":11155111,"address":"0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266","balances":[{"symbol":"ETH"}],"route":"proxied"})"));
        expect("a reply for THIS selection, case-folded", "is acted on", a.acted);
        expect("...and stamps freshness", "so the view may render", s.fresh);
        same("...with the route it came by", s.balancesRoute, QStringLiteral("proxied"));
    }
    {
        ScopedState s = screen();
        const Applied a = applyBalances(s, q(R"({"ok":false,"error":"no node"})"));
        expect("a refusal names nothing and is this call's own answer", "acted on", a.acted);
        same("...leaving the figures UNKNOWN, not the previous ones", s.balances, QString());
        same("...with the backend's words", a.error, QStringLiteral("balances: no node"));
    }

    std::printf("\nthe quote: paired with the request it priced, and scoped like everything else\n");
    {
        ScopedState s = screen();
        applyQuote(s, q(R"({"ok":true,"chainId":11155111,"owner":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","amountOut":"5"})"), QStringLiteral("REQ1"), true);
        same("a quote for this account and chain lands", s.quoteRequest, QStringLiteral("REQ1"));
        applyQuote(s, q(R"({"ok":true,"chainId":1,"owner":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","amountOut":"9"})"), QStringLiteral("REQ2"), true);
        same("one for another chain withdraws rather than lands", s.quoteRequest, QString());
        applyQuote(s, q(R"({"ok":false,"error":"no route found"})"), QStringLiteral("REQ3"), true);
        same("an interactive refusal reaches the swap line", s.swapError, QStringLiteral("no route found"));
        s = screen();
        s.quote = QStringLiteral(R"({"ok":true,"chainId":11155111,"owner":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"})");
        s.quoteRequest = QStringLiteral("REQ1");
        applyQuote(s, q(R"({"ok":false,"error":"timeout"})"), QStringLiteral("REQ1"), false);
        expect("a timer tick's failure", "marks the standing figure stale", s.quoteStale);
        same("...and keeps it", s.quoteRequest, QStringLiteral("REQ1"));
        same("...saying nothing on the swap line", s.swapError, QString());
        expect("enterQuoteRequest", "withdraws on a changed request", enterQuoteRequest(s, QStringLiteral("REQ9")) && s.quoteRequest.isEmpty());
        s = screen();
        s.swapError = QStringLiteral("no answer within 8699ms");
        applyQuote(s, q(R"({"ok":true,"chainId":11155111,"owner":"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","amountOut":"5"})"), QStringLiteral("REQ1"), false);
        same("a tick that succeeds after a failed keystroke clears the refusal", s.swapError, QString());
    }

    std::printf("\nthis app's swaps, grouped by the backend\n");
    {
        ScopedState s = screen();
        const SwapsApplied a = applySwaps(s, QStringLiteral(R"({"ok":true,"chainId":11155111,"address":"%1","stillDue":true,"swaps":[{"requestId":"snd_2","status":"pending"},{"requestId":"snd_1","status":"confirmed"}]})").arg(q(ALICE)));
        expect("the reply for this selection", "is acted on", a.acted);
        expect("...and the sweep runs while something is due", "Run", a.sweep == SweepVerdict::Run);
        const QJsonArray groups = QJsonDocument::fromJson(s.swaps.toUtf8()).array();
        expect("the backend's order is kept", "snd_2 first",
               groups.size() == 2 && groups.at(0).toObject().value(QStringLiteral("requestId")).toString() == QStringLiteral("snd_2"));
        const SwapsApplied done = applySwaps(s, QStringLiteral(R"({"ok":true,"chainId":11155111,"address":"%1","stillDue":false,"swaps":[]})").arg(q(ALICE)));
        expect("nothing due", "stops the sweep", done.sweep == SweepVerdict::Stop);
        same("...and an empty list is an answer", s.swaps, QStringLiteral("[]"));
    }
    {
        ScopedState s = screen();
        const SwapsApplied a = applySwaps(s, QStringLiteral(R"({"ok":true,"chainId":1,"address":"%1","stillDue":false,"swaps":[{"requestId":"x"}]})").arg(q(ALICE)));
        expect("swaps for another chain", "are dropped whole", !a.acted);
        same("...leaving the list as it was", s.swaps, QStringLiteral("[]"));
        const SwapsApplied f = applySwaps(s, q(R"({"ok":false,"error":"no node"})"));
        expect("a read that FAILED", "says nothing about the sweep", f.sweep == SweepVerdict::Unchanged);
        same("...and the list is UNKNOWN, not empty", s.swaps, QString());
    }

    std::printf("\nthe request the backend is handed\n");
    {
        const QString form = q(R"({"from":"0xf39F","tokenIn":"0xA0b8","tokenOut":"ETH","amountUnits":"1000","decimalsIn":6})");
        const QJsonObject r = parseObject(withChain(form, 11155111));
        expect("the form goes as it is", "same fields", r.value(QStringLiteral("amountUnits")).toString() == QStringLiteral("1000")
               && r.value(QStringLiteral("decimalsIn")).toInt() == 6);
        expect("...on the chain on screen", "11155111", r.value(QStringLiteral("chainId")).toInt() == 11155111);
        for (const char *nothing : {"", "0", "0.00", ".", " 0 "})
            expect(nothing, "is nothing to price", isNothing(QStringLiteral(R"({"amountUnits":"%1"})").arg(q(nothing))));
        expect("0.5", "is an amount", !isNothing(q(R"({"amountUnits":"0.5"})")));
        expect("letters", "are the backend's to refuse, in words", !isNothing(q(R"({"amountUnits":"ten"})")));
    }

    std::printf("\nthe catalogue, in pages: a later page grows the picker's answer, or is nothing\n");
    {
        ScopedState s = screen();
        applyCatalogue(s, QStringLiteral(R"({"ok":true,"chainId":11155111,"total":5,"offset":0,"shown":2,"hasMore":true,"listed":3,"tokens":[{"symbol":"A"},{"symbol":"B"}]})"));
        const QString second = QStringLiteral(R"({"ok":true,"chainId":11155111,"total":5,"offset":2,"shown":2,"hasMore":true,"listed":3,"tokens":[{"symbol":"C"},{"symbol":"D"}]})");
        expect("the second page is applied", "acted", applyCataloguePage(s, second, 2).acted);
        const QJsonObject m = parseObject(s.catalogue);
        const QJsonArray rows = m.value(QStringLiteral("tokens")).toArray();
        expect("...its rows follow the first page's", "A B C D",
               rows.size() == 4 && rows.at(3).toObject().value(QStringLiteral("symbol")).toString() == QStringLiteral("D"));
        expect("...shown counts every row held", "4", m.value(QStringLiteral("shown")).toInt() == 4);
        expect("...and the picker is told to grow rather than start over", "appended",
               m.value(QStringLiteral("appended")).toBool());
        const QString before = s.catalogue;
        expect("a page whose offset is not where the rows end", "is nothing",
               !applyCataloguePage(s, second, 3).acted && s.catalogue == before);
        expect("a page for another chain", "is nothing",
               !applyCataloguePage(s, QStringLiteral(R"({"ok":true,"chainId":1,"offset":4,"total":9,"tokens":[{"symbol":"X"}]})"), 4).acted && s.catalogue == before);
        const Applied f = applyCataloguePage(s, QStringLiteral(R"({"ok":false,"chainId":11155111,"error":"down"})"), 4);
        expect("a page that failed", "keeps the rows and says why", f.acted && !f.error.isEmpty() && s.catalogue == before);
        expect("the last page ends it", "hasMore false",
               applyCataloguePage(s, QStringLiteral(R"({"ok":true,"chainId":11155111,"total":5,"offset":4,"shown":1,"hasMore":false,"listed":3,"tokens":[{"symbol":"E"}]})"), 4).acted
               && !parseObject(s.catalogue).value(QStringLiteral("hasMore")).toBool()
               && parseObject(s.catalogue).value(QStringLiteral("shown")).toInt() == 5);
    }

    std::printf("\nthe selection: withdrawal on a move\n");
    {
        ScopedState s = screen();
        s.quote = QStringLiteral("{\"ok\":true}"); s.quoteRequest = QStringLiteral("R"); s.catalogue = QStringLiteral("{\"ok\":true}");
        expect("the same selection, recased", "does not move", !enterScope(s, selectionOf(q("0xF39FD6E51AAD88F6F4CE6AB8827279CFFFB92266"), QStringLiteral(R"({"chainId":11155111})"))));
        expect("another account", "moves", enterScope(s, selectionOf(q("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"), QStringLiteral(R"({"chainId":11155111})"))));
        same("...withdrawing the balances", s.balances, QString());
        same("...the swaps", s.swaps, QString());
        same("...the quote", s.quoteRequest, QString());
        same("...but not the chain's catalogue", s.catalogue, QStringLiteral("{\"ok\":true}"));
        expect("another chain", "moves", enterScope(s, selectionOf(q(ALICE), QStringLiteral(R"({"chainId":1})"))));
        same("...withdrawing the catalogue too", s.catalogue, QString());
        same("...and the tokens", s.tokens, QString());
    }

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
