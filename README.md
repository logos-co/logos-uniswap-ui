# uniswap_ui

Swap any two tokens on Uniswap from the wallet's accounts, on whichever network the wallet
is on.

Information design follows the wallet, which follows MetaMask: one question per screen, and
**the active network visible at all times** — a user must never be able to mistake which
chain they are swapping on. Three sections. **Swap**: what you sell, what you buy, and under
the two cards the rate, the minimum you receive, the price impact, the route, the pool fee
and the network fee. **Activity**: the swaps this app made, one row per swap however many
transactions it took. **Settings**: slippage and deadline, and the two hand-offs to the apps
that manage accounts and token lists.

## What this module cannot do

It holds no secret and **sends nothing**. It asks `uniswap_module` for a quote and the calls
that make it, and asks `tx_sender_module` to send them; the human's yes is taken by
`evm_signer_ui`, once, for every call of the swap. There is no password parameter anywhere
in `src/uniswap_ui.rep`, and there never may be; `doctests/assert_ui.py` asserts the absence.

It never moves the network. The wallet's Networks screen does, and this view follows.

## Why a swap is one approval and, often, two transactions

A swap from a token needs the router to be allowed to take it, and an ERC-20 allowance is
its own transaction. `uniswap_module` reads the allowance in the same batch as the quote and
builds the approval only when it is short — for **exactly the amount**, never infinite, and
zeroed first where the allowance is non-zero and short (USDT refuses the direct change).
`tx_sender_module` reserves one nonce per call, asks the keystore **once** for the bundle,
and broadcasts them in order after the approval; the review dialog lists every transaction
the signer will be asked for, and the outcome dialog names every hash.

## What a figure on screen belongs to

Every balance, quote, swap row and route label means something only against the account
**and** network it was read under. When either moves, everything narrower than the new
selection is withdrawn before the new selection is published — an em-dash, never a zero, and
never the previous selection's number. `enterScope` in `src/uniswap_ui_scope.h` performs the
withdrawal, and the backend reaches it only by overriding the two generated selection
setters onto it.

The quote is paired with the **request** it priced: the Swap page renders figures only while
`quoteRequestJson` still equals what the form describes, so an edited amount withdraws the
previous output the instant it is typed rather than when the re-quote lands.

## Money

Amounts are exact integer work, in `src/uniswap_ui_units.h`, tested by
`doctests/test_units.cpp`. A typed amount with more decimal places than the token has is
refused in words, never rounded; a displayed amount is truncated to five places, never
rounded up; "<0.00001" is an amount that is not nothing. The one double in the file is the
rate line, which is a display of a ratio and says so.

The network fee is shown as **"at most"**: `maxFeePerGas × gasLimit` is a ceiling the user
is not charged. Every leg's limit is `fee_module`'s estimate, the swap behind its approval
estimated with that allowance applied; `uniswap_module`'s `gasLimitHint` is not sent, so the
figure the user reads is the chain's, not this app's guess.

**Price impact** is the shortfall of the quoted rate against the rate a thousandth of the
amount fetches on the same route. Uniswap's own thresholds: a warning colour from 3%, and
from 5% the button reads "Swap anyway" and waits for an acknowledgement that resets with
every change to the form.

## Whose swap is it

The sender stamps every row with the `origin` the runtime attested, and this app tags every
call it asks for with `meta.app = "uniswap_ui"`. Activity is built from the tag — it is how
this app finds its rows in a history it shares with the wallet — and the swap's own screen
shows the origin beside it. The wallet's Activity shows the same rows as calls, titled with
the labels this app gave them.

## Testing

```bash
doctests/run_tables.sh          # test_units.cpp, test_apply.cpp, then the two view probes
python3 doctests/assert_ui.py   # the claims a source file can answer for
```

`doctests/test_apply.cpp` runs every guard that decides whether a reply reaches the screen,
and every shape this view hands its two modules. `doctests/probe_swap.qml` and
`probe_intents.qml` stand the view up under an offscreen Qt with a fabricated backend and
assert what it **says**: every state of the swap button, the quote rows, the review, the
signer hand-off and each of its answers.

`doctests/uniswap-ui-e2e.test.yaml` builds the plugin and the seven modules under it, stands
a real `logos-standalone-app` up, and drives the three sections over the QML inspector —
hermetic, with an empty keystore. `doctests/uniswap-anvil-swap.test.yaml` runs the three
modules the way the view runs them, with `logosctl` alone, against a local Anvil chain
holding a mock V2 router: quote, build, one approval through `evm_signer_cli`, two
transactions, both receipts, and the chain read back with `cast`.

## Building

```bash
nix build .#lgx-portable   # the installable package (Basecamp / logosctl)
nix build .#install        # the dev variant, for logos-standalone-app
```

Until `logos-evm-tx-sender-module` is published, point the input at a checkout:

```bash
nix build .#install --override-input tx_sender_module path:../logos-evm-tx-sender-module \
  --override-input eth_wallet_backend path:../logos-eth-wallet-backend \
  --override-input uniswap_module path:../uniswap-module --no-write-lock-file
```
