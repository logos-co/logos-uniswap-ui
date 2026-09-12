// The unit arithmetic, as a table. A swap moves base units and a human types token units;
// every conversion between them is exact integer work here, and this runs each rule.
//
//   c++ -std=c++17 -fPIC -I../src $(pkg-config --cflags --libs Qt6Core) test_units.cpp -o /tmp/t && /tmp/t
#include <cstdio>
#if defined(__aarch64__)
#  include <arm_acle.h>
#endif
#include "uniswap_ui_units.h"

namespace {
int failures = 0;
void same(const char *label, const QString &got, const char *want)
{
    const bool ok = got == QString::fromUtf8(want);
    if (!ok) ++failures;
    std::printf("  %s  %-58s got=%s\n", ok ? "PASS" : "FAIL", label, got.isNull() ? "<null>" : got.toUtf8().constData());
}
void expect(const char *label, bool got)
{
    if (!got) ++failures;
    std::printf("  %s  %s\n", got ? "PASS" : "FAIL", label);
}
} // namespace

int main()
{
    std::printf("token units to base units: exact, and refused rather than rounded\n");
    same("1.5 USDC (6)", toBaseUnits("1.5", 6), "1500000");
    same("a whole number", toBaseUnits("1000", 6), "1000000000");
    same("a leading dot", toBaseUnits(".5", 18), "500000000000000000");
    same("a trailing dot", toBaseUnits("5.", 18), "5000000000000000000");
    same("one wei", toBaseUnits("0.000000000000000001", 18), "1");
    same("zero is an amount of nothing, not a refusal", toBaseUnits("0", 18), "0");
    same("0.0 too", toBaseUnits("0.0", 6), "0");
    same("leading zeros go", toBaseUnits("007", 2), "700");
    same("whitespace is trimmed", toBaseUnits("  2 ", 0), "2");
    same("too many places is refused, never rounded", toBaseUnits("1.1234567", 6), "");
    same("letters are refused", toBaseUnits("ten", 6), "");
    same("a sign is refused", toBaseUnits("-1", 6), "");
    same("a comma is refused", toBaseUnits("1,5", 6), "");
    same("nothing is refused", toBaseUnits("", 6), "");
    same("a lone dot is refused", toBaseUnits(".", 6), "");

    std::printf("\nbase units to token units\n");
    same("exact 1500000 at 6", fromBaseUnitsExact("1500000", 6), "1.5");
    same("exact one wei", fromBaseUnitsExact("1", 18), "0.000000000000000001");
    same("exact whole", fromBaseUnitsExact("5000000000000000000", 18), "5");
    same("exact zero", fromBaseUnitsExact("0", 18), "0");
    same("exact at 0 decimals", fromBaseUnitsExact("42", 0), "42");
    same("display truncates to five places", fromBaseUnits("333277787035494084", 18), "0.33327");
    same("...never rounding up", fromBaseUnits("199999", 6), "0.19999");
    same("display of dust", fromBaseUnits("1", 18), "<0.00001");
    same("display of zero", fromBaseUnits("0", 18), "0");
    same("display keeps short fractions whole", fromBaseUnits("1500000", 6), "1.5");
    same("garbage is nothing", fromBaseUnits("abc", 6), "");

    std::printf("\ncomparing amounts\n");
    expect("smaller by length", compareBase("999", "1000") < 0);
    expect("larger by length", compareBase("1000", "999") > 0);
    expect("equal", compareBase("0001000", "1000") == 0);
    expect("same length, lexical", compareBase("1999", "2000") < 0);
    expect("a balance short of the amount", compareBase("5000000000000", "5000000000001") < 0);

    std::printf("\nthe rate line\n");
    same("1000 USDC -> 0.33 ETH", rateOf("1000000000", 6, "333277787035494084", 18), "0.000333278");
    same("the inverse", rateOf("333277787035494084", 18, "1000000000", 6), "3000.5");
    same("nothing in", rateOf("0", 6, "5", 18), "");
    same("garbage", rateOf("x", 6, "5", 18), "");

    std::printf("\nRESULT: %s\n", failures ? "FAILED" : "ALL PASS");
    return failures ? 1 : 0;
}
