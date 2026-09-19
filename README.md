# uniswap_ui

Swap any two EVM assets on Uniswap. The app is a view over `uniswap_backend`, which composes
the reusable chain, token, asset, account, fee, quote and sender modules; this view calls no
other module, and `eth_wallet_backend` is deliberately not in the graph.

Information design follows the wallet, which follows MetaMask: one question per screen, and
**the active network visible at all times** — the selector follows the backend's initial
choice and defaults to the first enabled mainnet when no prior choice exists, so a user must
never be able to mistake which chain they are swapping on. Three sections. **Swap**: what you
sell, what you buy, and under
the two cards the rate, the minimum you receive, the price impact, the route, the pool fee
and the network fee. **Activity**: the swaps this app made, one row per swap however many
transactions it took. **Settings**: slippage and deadline, and the two hand-offs to the apps
that manage accounts and token lists.

## What this module cannot do

It holds no secret and **sends nothing**. It asks `uniswap_backend`, which quotes through
`uniswap_module` and hands the calls to `tx_sender_module`; the human's yes is taken by
`evm_signer_ui`, once, for every call of the swap. There is no password parameter anywhere
in `src/uniswap_ui.rep`, and there never may be; `doctests/assert_ui.py` asserts the absence.

Its chain dropdown is UI-local. Choices are the backend's networks: the enabled chains in
`eth_rpc_module`'s device-wide scope that Uniswap is deployed on. When the old choice leaves
that set, the app chooses the first mainnet (or the first remaining chain).

This app holds no keystore client at all. Accounts reach it through `uniswap_backend`, whose
keystore client only reads (its source guard asserts it), and every transaction leaves through
`tx_sender_module`, which owns the approval flow.

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

Amounts are exact integer work, done by `uniswap_backend` (`rust-lib/src/units.rs` there,
with its tests); the quote arrives with every display string already derived. A typed amount with more decimal places than the token has is
refused in words, never rounded; a displayed amount is truncated to five places, never
rounded up; "<0.00001" is an amount that is not nothing. The one double in the file is the
rate line, which is a display of a ratio and says so.

The network fee is shown as **"at most"**: `maxFeePerGas × gasLimit` is a ceiling the user
is not charged. Every leg's limit is `fee_module`'s estimate, the swap behind its approval
estimated with that allowance applied; `uniswap_module`'s `gasLimitHint` is not sent, so the
figure the user reads is the chain's, not this app's guess. Beside it: each call's gas limit,
the max and priority fee in gwei, and the nonces the calls take.

The fee tiers, those figures, the Advanced section and the review are the wallet's own, from
[logos-evm-tx-kit](https://github.com/logos-co/logos-evm-tx-kit), vendored in `src/qml/kit`
and checked in CI against the commit in `src/qml/kit/VERSION`. Advanced sets the max and
priority fee (both travel together), a gas limit per call, and a nonce for a one-transaction
swap; a swap with an approval shows its two nonces read-only, since a nonce replaces one
pending transaction.

**Price impact** is the shortfall of the quoted rate against the rate a thousandth of the
amount fetches on the same route. Uniswap's own thresholds: a warning colour from 3%, and
from 5% the button reads "Swap anyway" and waits for an acknowledgement that resets with
every change to the form.

## Whose swap is it

The sender stamps every row with the `origin` the runtime attested — `uniswap_backend`, the
module that asks it — and the backend tags every call with `meta.app = "uniswap_ui"` and
`meta.via`, the module that asked the backend. The Signer's purpose line names both: "Swap …
on Uniswap, via uniswap_ui [asked by uniswap_backend]". Activity is built from the tag — it
is how this app finds its rows in a history it shares with the wallet — and the swap's own
screen shows who asked: "uniswap_ui, through uniswap_backend". The wallet's Activity shows
the same rows as calls, titled with the labels the backend gave them.

## Testing

```bash
doctests/run_tables.sh          # test_apply.cpp, then the two view probes
python3 doctests/assert_ui.py   # the claims a source file can answer for
```

`doctests/test_apply.cpp` runs every guard that decides whether a reply reaches the screen,
and the request this view hands its backend. The swap rules themselves (the form, the
sender's request, the purpose, the grouping of history) are the backend's, tested there.
`doctests/probe_swap.qml` and `probe_intents.qml` stand the view up under an offscreen Qt with
a fabricated backend and assert what it **says**: every state of the swap button, the quote rows, the review, the
signer hand-off and each of its answers.

`doctests/uniswap-ui-e2e.test.yaml` builds the plugin, the backend and the reusable modules
under it, stands a real `logos-standalone-app` up, and drives the three sections over the QML
inspector — hermetic, with an empty keystore. The headless swap against a local Anvil chain
lives with the backend, in `logos-uniswap-backend/doctests/`.

## Building

```bash
nix build .#lgx-portable   # the installable package (Basecamp / logosctl)
nix build .#install        # the dev variant, for logos-standalone-app
```

For a local composition, point the backend at its checkout (and the backend's own inputs at
theirs, the same way):

```bash
nix build .#install --no-write-lock-file \
  --override-input uniswap_backend path:../logos-uniswap-backend
```
