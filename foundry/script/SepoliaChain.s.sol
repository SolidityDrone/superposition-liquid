// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title SepoliaChain
/// @notice Ethereum Sepolia testnet addresses (verified on-chain Sep 2026):
///         Aqua registry + SwapVM router are the same vanity addresses as mainnet.
library SepoliaChain {
    string internal constant RPC_URL = "https://ethereum-sepolia.publicnode.com";

    // Aqua — same vanity address as mainnet
    address internal constant AQUA = 0x1111113CCf1426A8E30e2bfF5E005d929bF6a90a;
    address internal constant SWAPVM_ROUTER = 0x111111338c5091E8440b67B168bAe16a668AC0De;

    // Tokens
    address internal constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14; // Sepolia WETH
    address internal constant USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8; // Aave testnet USDC
    address internal constant USDT = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // Aave testnet USDT

    // Aave v3 (Sepolia market)
    address internal constant AAVE_POOL = 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951;
    address internal constant A_WETH = 0x5b071b590a59395fE4025A0Ccc1FcC931AAc1830;
    address internal constant A_USDC = 0x16dA4541aD1807f4443d92D26044C1147406EB80;
    address internal constant FAUCET = 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D; // permissionless mint(token,to,amount)
    address internal constant STATA_FACTORY = 0xd210dFB43B694430B8d31762B5199e30c31266C8; // legacy getStaticAToken()

    // Uniswap v4
    address internal constant POOL_MANAGER = 0xE03A1074c86CFeDd5C142C4F04F1a1536e203543;

    // Deployed SuperPosition stack (Sep 2026, see script/sepolia/DeploySepolia.s.sol)
    address internal constant MAKER_CONFIG = 0xF56EBe6386F40969A9721C6aB3fa07BEaD1Bd926;
    address internal constant SUPERPOSITION_ROUTER = 0x201D78030bed2d81F827B7650E2CB7C00Ea0c9EC;
    address internal constant AAVE_ADAPTER = 0xd915d3Db7f18f75D67c63B3Aa00872fbCE793c57;
    address internal constant ERC4626_ADAPTER = 0xb1B9955600DfAF8987da8c9D0A37F2d2ee4B8752;
    address internal constant VAULT_USDC = 0x4F32F6bE82407E7956E5752672677542379a1ec8;
    address internal constant VAULT_USDT = 0x0d98E00F0EFfE80a8Afd23FbA7cd0483E46CAa8D;
    address internal constant SUPERPOSITION_HOOK = 0x6A7A2C6495A16f0a4c77E771f8A3945ee3494aC0;
    address internal constant SUPERPOSITION_UNI_ADAPTER = 0x1be3291f7Ef08e56f0141007F49846fB07794C8B;
    address internal constant FAUCET_BATCH = 0xE05742c33bf6b347919B26934fa1Df9eF056F156; // SepoliaFaucetBatch (mintAll in one tx)

    // Chainlink price feeds
    address internal constant CHAINLINK_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address internal constant CHAINLINK_USDC_USD = 0xA2f22CF35C20FA56c3DAA4C560e76531A4573ad2; // Sepolia USDC/USD

    // Stargate V2 (Sepolia)
    address internal constant STARGATE_POOL = 0x4985b8fcEA3659FD801a5b857dA1D00e985863F0; // StargatePoolUSDC
    address internal constant STARGATE_STAKING = 0xE62F51D9DA2b082abed838E9Ac48D0EDFFbfedaE;
}
