{
  description = "Logos uniswap_ui — swap any two tokens on Uniswap from the wallet's accounts. Holds no key material.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Every dependency builds against THIS module-builder. Without the follows each drags
    # its own, and a skewed generated ABI segfaults the module inside provider init.
    eth_wallet_backend = {
      url = "github:logos-co/logos-eth-wallet-backend";
      inputs.logos-module-builder.follows = "logos-module-builder";
      # One sender, one lidl: the wallet backend sends through the same module this view
      # does, and two pins of it would generate two clients for one name.
      inputs.tx_sender_module.follows = "tx_sender_module";
    };
    uniswap_module = {
      url = "github:logos-co/logos-evm-uniswap-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    tx_sender_module = {
      url = "github:logos-co/logos-evm-tx-sender-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
  };

  # mkLogosQmlModule, NOT mkLogosModule: the generic builder compiles the plugin but never
  # assembles the QML, so the .lgx step then fails with "view file not found in staged payload".
  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
