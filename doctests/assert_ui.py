#!/usr/bin/env python3
"""Source assertions for uniswap_ui: the claims a file can answer for, with no app.

Everything here is a grep with a reason. The rules a table can RUN live in test_apply.cpp
and test_units.cpp; the bindings live in the probes. What is left for a grep is what neither
can see, asserted as an ABSENCE where possible: no password anywhere on the contract, no
backend-authored string rendered as markup, no scoped setter outside publishScope.
"""
import re
import sys
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE.parent / "src"
REP = (SRC / "uniswap_ui.rep").read_text()
QML = (SRC / "qml" / "UniswapView.qml").read_text()
CPP = (SRC / "uniswap_ui_backend.cpp").read_text()
HDR = (SRC / "uniswap_ui_backend.h").read_text()
META = json.loads((HERE.parent / "metadata.json").read_text())
# A dependency entry is a bare name or `{ name, version }`; compare names, or an
# object entry would never equal the string being looked for.
DEPS = [d if isinstance(d, str) else d["name"] for d in META["dependencies"]]

failures = 0


def check(label, got, want=True):
    global failures
    ok = got == want
    if not ok:
        failures += 1
    print(f"  {'PASS' if ok else 'FAIL'}  {label}   got={got!r}")


print("0. the contract carries no secret, and never may")
REP_CODE = "\n".join(l.split("//")[0] for l in REP.splitlines())
check("no password parameter on the .rep", re.search(r"password", REP_CODE, re.I) is None)
check("...though the comment forbidding one is there", "NO password" in REP)
check("...nor on the backend", re.search(r"password|privateKey|mnemonic|seed", CPP + HDR, re.I) is None)
check("the view never calls a module itself", "logos.module(" in QML and ".call(" not in QML)
check("the only intents are the three declared",
      sorted(set(re.findall(r'logos\.request\("([a-z_.]+)"', QML)) | {m for m in re.findall(r'askFor\("([a-z_.]+)"', QML)}),
      ["evm.accounts.manage", "evm.signing.approve", "evm.token_lists.configure"])

print("0a. backend-authored strings are rendered as plain text")
# Every LogosText whose text reads a backend property or a module reply carries PlainText.
# Judged on the `text:` expression alone: a `visible:` that reads a reply renders nothing.
blocks = re.findall(r"LogosText \{(.*?)\n\s*\}", QML, re.S)
def text_expr(block):
    m = re.search(r"\n\s*text: (.*?)(?=\n\s*[a-zA-Z.]+: |\n\s*\}|$)", block, re.S)
    return m.group(1) if m else ""
# A component's own property (`row.label`, `card.heading`) is authored here; a reply's is not.
rendered = [b for b in blocks
            if re.search(r"backend\.|modelData\.|root\.swapOutcome|\.error\b|\.reason\b|\.message\b|\.symbol\b|\.name\b", text_expr(b))
            and not re.match(r"\s*(row|card|glyph)\.", text_expr(b))]
lacking = [b.strip().splitlines()[0] for b in rendered if "textFormat: Text.PlainText" not in b]
check("every LogosText whose text is a reply sets PlainText", lacking, [])
check("...and that rule caught a real number of them", len(rendered) >= 12)

print("0b. the scoped state reaches the view through one door")
setters = re.findall(r"\bset(BalancesJson|BalancesRoute|QuoteJson|QuoteRequestJson|QuoteStale|SwapError|SwapsJson|TokensJson|CatalogueJson|FeeTiersJson|VerifiedProxyJson|ScopedDataFresh)\(", CPP)
body = CPP[CPP.index("void UniswapUiBackend::publishScope"):]
body = body[:body.index("\n}\n")]
inside = re.findall(r"\bset(BalancesJson|BalancesRoute|QuoteJson|QuoteRequestJson|QuoteStale|SwapError|SwapsJson|TokensJson|CatalogueJson|FeeTiersJson|VerifiedProxyJson|ScopedDataFresh)\(", body)
check("no scoped setter is called outside publishScope", len(setters), len(inside))
check("...and publishScope writes all twelve", sorted(set(inside)), sorted({
    "BalancesJson", "BalancesRoute", "QuoteJson", "QuoteRequestJson", "QuoteStale", "SwapError",
    "SwapsJson", "TokensJson", "CatalogueJson", "FeeTiersJson", "VerifiedProxyJson", "ScopedDataFresh"}))

print("0c. every module call is bounded")
async_calls = re.findall(r"AsyncResult\(", CPP)
timeouts = re.findall(r"Timeout\(k(?:Call|SwapCall)BudgetMs\)", CPP)
check("every AsyncResult call carries a budget", len(async_calls), len(timeouts))
check("...and there are calls to bound", len(async_calls) >= 8)
check("a quote and a swap wait for the backend's whole allowance",
      len(re.findall(r"Timeout\(kSwapCallBudgetMs\)", CPP)), 2)
sync_calls = re.findall(r"modules\(\)\.[a-z_]+\.([a-z_]+)\(", CPP)
check("the synchronous calls are the cheap reads and the cancel alone",
      sorted(set(sync_calls)), sorted({"networks", "tokens", "accounts", "cancel_swap"}))

print("0d. this view has one dependency, its backend")
check("uniswap_backend is the only dependency", DEPS, ["uniswap_backend"])
check("...and the only client the view's C++ calls", sorted(set(re.findall(r"modules\(\)\.([a-z_]+)\.", CPP))),
      ["uniswap_backend"])
check("...so no module the backend composes is reached around it",
      re.search(r"keystore_module|tx_sender_module|uniswap_module|eth_wallet_backend", CPP + HDR) is None)
check("the chain selector is part of the contract and view",
      "selectNetwork(int chainId)" in REP and 'objectName: "chainPicker"' in QML)
check("the chain selector follows both halves of backend initialization",
      "onModelChanged: syncIndex()" in QML
      and "function onNetChanged() { chainPicker.syncIndex() }" in QML)

print("0e. the swap is offered only when the quote says it can be paid for")
check("the button is enabled on the ready state alone",
      re.search(r'objectName: "swapButton".*?enabled: root\.ready && !root\.swapSubmitting\s*&& swapForm\.state === "ready"', QML, re.S) is not None)
check("the review confirm is what submits", "root.backend.submitSwap(swapForm.formRequest)" in QML)
check("...and the swap button only opens the review", re.search(r'objectName: "swapButton".*?onClicked: reviewDialog\.open\(\)', QML, re.S) is not None)

print()
print("RESULT:", f"{failures} FAILED" if failures else "ALL PASS")
sys.exit(1 if failures else 0)
