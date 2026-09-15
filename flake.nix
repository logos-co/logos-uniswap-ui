{
  description = "Logos uniswap_ui — compose reusable EVM modules into a Uniswap app. Holds no key material.";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # Every dependency builds against THIS module-builder. Without the follows each drags
    # its own, and a skewed generated ABI segfaults the module inside provider init.
    eth_rpc_module = {
      url = "github:logos-co/logos-evm-eth-rpc-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    token_list_module = {
      url = "github:logos-co/logos-evm-token-list-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    keystore_module = {
      url = "github:logos-co/logos-evm-keystore-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
    };
    fee_module = {
      url = "github:logos-co/logos-evm-fee-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
    };
    uniswap_module = {
      url = "github:logos-co/logos-evm-uniswap-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
    };
    tx_sender_module = {
      url = "github:logos-co/logos-evm-tx-sender-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
      inputs.fee_module.follows = "fee_module";
      inputs.keystore_module.follows = "keystore_module";
    };
    evm_assets_module = {
      url = "github:logos-co/logos-evm-assets-module";
      inputs.logos-module-builder.follows = "logos-module-builder";
      inputs.eth_rpc_module.follows = "eth_rpc_module";
      inputs.token_list_module.follows = "token_list_module";
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
