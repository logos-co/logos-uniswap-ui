// Every guard that decides whether a reply reaches the screen, and every shape this view
// hands its two modules, as a table. The transitions live in src/uniswap_ui_apply.h and are
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
const char *USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const char *ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

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

QString row(const char *hash, const char *reqId, int leg, const char *status, const char *kind, const char *app, double ts)
{
    return QStringLiteral(R"({"hash":"%1","requestId":"%2","leg":%3,"legs":2,"status":"%4","timestamp":%5,"label":"L%3","origin":"host","to":"0x1","meta":{"app":"%6","kind":"%7","symbolIn":"USDC","symbolOut":"ETH","amountIn":"1000000000","decimalsIn":6,"amountOut":"5","decimalsOut":18}})")
        .arg(hash, reqId).arg(leg).arg(status).arg(ts).arg(app, kind);
}
} // namespace

int main()
{
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

    std::printf("\nthis app's swaps, out of a history it shares with the wallet\n");
    {
        const QString rows = QStringLiteral("[%1,%2,%3,%4]")
            .arg(row("0xa1", "snd_1", 1, "confirmed", "swap", "uniswap_ui", 200),
                 row("0xa0", "snd_1", 0, "confirmed", "approve", "uniswap_ui", 199),
                 row("0xb0", "snd_2", 0, "pending", "swap", "uniswap_ui", 300),
                 row("0xc0", "", 0, "confirmed", "native", "", 400));
        ScopedState s = screen();
        const SwapsApplied a = applySwaps(s, QStringLiteral(R"({"ok":true,"chainId":11155111,"address":"%1","stillDue":true,"transactions":%2})").arg(q(ALICE), rows), QStringLiteral("uniswap_ui"));
        expect("the reply for this selection", "is acted on", a.acted);
        expect("...and the sweep runs while something is due", "Run", a.sweep == SweepVerdict::Run);
        const QJsonArray groups = QJsonDocument::fromJson(s.swaps.toUtf8()).array();
        expect("the wallet's own row is not one of ours", "two bundles", groups.size() == 2);
        same("newest first", groups.at(0).toObject().value(QStringLiteral("requestId")).toString(), QStringLiteral("snd_2"));
        const QJsonObject b1 = groups.at(1).toObject();
        same("the two-leg bundle is one entry", b1.value(QStringLiteral("requestId")).toString(), QStringLiteral("snd_1"));
        expect("...its legs in order", "approve then swap", b1.value(QStringLiteral("legs")).toArray().at(0).toObject().value(QStringLiteral("leg")).toInt() == 0);
        same("...titled by the swap leg's label", b1.value(QStringLiteral("label")).toString(), QStringLiteral("L1"));
        same("...with the swap leg's meta", b1.value(QStringLiteral("swap")).toObject().value(QStringLiteral("kind")).toString(), QStringLiteral("swap"));
        same("...both hashes", QString::number(b1.value(QStringLiteral("hashes")).toArray().size()), QStringLiteral("2"));
        same("...settled as a whole", b1.value(QStringLiteral("status")).toString(), QStringLiteral("confirmed"));
        same("the pending one says so", groups.at(0).toObject().value(QStringLiteral("status")).toString(), QStringLiteral("pending"));
        same("...and carries who asked, as the sender attested", b1.value(QStringLiteral("origin")).toString(), QStringLiteral("host"));
    }
    {
        QJsonArray legs;
        legs.append(parseObject(row("0x1", "r", 0, "confirmed", "approve", "uniswap_ui", 1)));
        legs.append(parseObject(row("0x2", "r", 1, "failed", "swap", "uniswap_ui", 2)));
        same("an approval that landed and a swap that reverted is a FAILED swap", bundleStatus(legs), QStringLiteral("failed"));
        QJsonArray stalled;
        QJsonObject st = parseObject(row("0x3", "r", 0, "pending", "swap", "uniswap_ui", 3));
        st.insert(QStringLiteral("stalled"), true);
        stalled.append(st);
        same("a stalled leg is a stalled swap", bundleStatus(stalled), QStringLiteral("stalled"));
    }
    {
        ScopedState s = screen();
        const SwapsApplied a = applySwaps(s, QStringLiteral(R"({"ok":true,"chainId":1,"address":"%1","stillDue":false,"transactions":[]})").arg(q(ALICE)), QStringLiteral("uniswap_ui"));
        expect("a history for another chain", "is dropped whole", !a.acted);
        same("...leaving the list as it was", s.swaps, QStringLiteral("[]"));
        const SwapsApplied f = applySwaps(s, q(R"({"ok":false,"error":"no node"})"), QStringLiteral("uniswap_ui"));
        expect("a read that FAILED", "says nothing about the sweep", f.sweep == SweepVerdict::Unchanged);
        same("...and the list is UNKNOWN, not empty", s.swaps, QString());
    }

    std::printf("\nthe form, the module request, the sender request\n");
    {
        SwapForm f;
        const QString bad = parseSwapForm(q(R"({"from":"0xf39F","tokenIn":"ETH","tokenOut":"0xA0b8","amountUnits":"1.2345678901234567890123","decimalsIn":18})"), &f);
        expect("more places than the token has", "is refused in words", bad.contains(QStringLiteral("18 decimal places")));
        const QString ok = parseSwapForm(q(R"({"from":"0xf39F","tokenIn":"0xA0b8","tokenOut":"ETH","amountUnits":"1000","decimalsIn":6,"decimalsOut":18,"symbolIn":"USDC","symbolOut":"ETH","tier":"fast","slippageBps":100,"deadlineMins":20})"), &f);
        same("a good form parses", ok, QString());
        same("...to base units", f.amountIn, QStringLiteral("1000000000"));
        same("...keeping the tier", f.tier, QStringLiteral("fast"));
        const QString bps = parseSwapForm(q(R"({"from":"0xf39F","tokenIn":"0xA0b8","tokenOut":"ETH","amountUnits":"1","decimalsIn":6,"slippageBps":6000})"), &f);
        expect("slippage above 50%", "is refused", bps.contains(QStringLiteral("5000")));
        parseSwapForm(q(R"({"from":"0xf39F","tokenIn":"0xA0b8","tokenOut":"ETH","amountUnits":"1000","decimalsIn":6,"decimalsOut":18,"symbolIn":"USDC","symbolOut":"ETH","slippageBps":100})"), &f);
        const QJsonObject m = parseObject(swapModuleRequest(f, 1789000000));
        same("the module is asked with the owner", m.value(QStringLiteral("owner")).toString(), QStringLiteral("0xf39F"));
        same("...the base-unit amount", m.value(QStringLiteral("amountIn")).toString(), QStringLiteral("1000000000"));
        same("...the slippage", QString::number(m.value(QStringLiteral("slippageBps")).toInt()), QStringLiteral("100"));
        same("...and the deadline", QString::number(qint64(m.value(QStringLiteral("deadline")).toDouble())), QStringLiteral("1789000000"));
        expect("a quote asks for no deadline", "absent", !parseObject(swapModuleRequest(f, 0)).contains(QStringLiteral("deadline")));

        const QJsonObject built = parseObject(QStringLiteral(R"({"ok":true,"amountOut":"5","amountOutMin":"4","route":{"version":"V2"},"calls":[{"kind":"approve","to":"%1","value":"0x0","data":"0x09","gasLimitHint":60000,"label":"Approve USDC for Uniswap"},{"kind":"swap","to":"%2","value":"0x0","data":"0x18","gasLimitHint":180000,"label":"Swap USDC for ETH on Uniswap V2"}]})").arg(q(USDC), q(ROUTER)));
        const QJsonObject sr = parseObject(senderRequest(built, f, QStringLiteral("uniswap_ui"), QStringLiteral("P"), 11155111));
        const QJsonArray calls = sr.value(QStringLiteral("calls")).toArray();
        expect("the sender gets both calls", "in order", calls.size() == 2 && calls.at(0).toObject().value(QStringLiteral("label")).toString().startsWith(QStringLiteral("Approve")));
        expect("the approve leg carries no gas limit", "the sender estimates it", !calls.at(0).toObject().contains(QStringLiteral("gasLimit")));
        same("the swap leg carries its hint", calls.at(1).toObject().value(QStringLiteral("gasLimit")).toString(), QStringLiteral("180000"));
        const QJsonObject meta = calls.at(1).toObject().value(QStringLiteral("meta")).toObject();
        same("every leg is tagged as this app's", meta.value(QStringLiteral("app")).toString(), QStringLiteral("uniswap_ui"));
        same("...and carries what the swap was", meta.value(QStringLiteral("amountOutMin")).toString(), QStringLiteral("4"));
        same("the purpose names the amounts", swapPurpose(f, built), QStringLiteral("Swap 1000 USDC for at least 0.000000000000000004 ETH on Uniswap"));
        same("the tier rides along", sr.value(QStringLiteral("tier")).toString(), QStringLiteral("normal"));
        same("and the chain", QString::number(sr.value(QStringLiteral("chainId")).toInt()), QStringLiteral("11155111"));

        const QJsonObject merged = parseObject(mergedQuote(parseObject(QStringLiteral(R"({"ok":true,"chainId":11155111,"owner":"0xf39F","amountOut":"333277787035494084","amountOutMin":"331611398100316613","balanceIn":"5000000000000"})")), q(R"({"ok":true,"feeCeilingWeiDisplay":"0.0004"})"), f));
        same("the merged quote names the account", merged.value(QStringLiteral("from")).toString(), QStringLiteral("0xf39F"));
        same("...carries the display of the output", merged.value(QStringLiteral("amountOutDisplay")).toString(), QStringLiteral("0.33327"));
        same("...and of the minimum", merged.value(QStringLiteral("amountOutMinDisplay")).toString(), QStringLiteral("0.33161"));
        same("...the rate", merged.value(QStringLiteral("rate")).toString(), QStringLiteral("0.000333278"));
        expect("...whether the balance covers it", "it does", merged.value(QStringLiteral("insufficientBalance")).toBool() == false);
        same("...and the sender's pricing under fee", merged.value(QStringLiteral("fee")).toObject().value(QStringLiteral("feeCeilingWeiDisplay")).toString(), QStringLiteral("0.0004"));
        const QJsonObject nofee = parseObject(mergedQuote(parseObject(QStringLiteral(R"({"ok":true,"chainId":11155111,"owner":"0xf39F","amountOut":"5","amountOutMin":"4","balanceIn":"1"})")), QString(), f));
        expect("a sender that did not answer", "is a fee that failed, and the quote still stands", nofee.value(QStringLiteral("ok")).toBool() && nofee.value(QStringLiteral("fee")).toObject().value(QStringLiteral("ok")).toBool() == false);
        expect("a balance short of the amount", "says so", nofee.value(QStringLiteral("insufficientBalance")).toBool());
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
