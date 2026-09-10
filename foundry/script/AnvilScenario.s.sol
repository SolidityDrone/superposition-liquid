// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { ISwapVM } from "@1inch/swap-vm/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/libs/TakerTraits.sol";
import { FeeArgsBuilder } from "@1inch/swap-vm/instructions/Fee.sol";

import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { ERC4626Adapter } from "src/adapters/ERC4626Adapter.sol";
import { StargateAdapter } from "src/adapters/stargate/StargateAdapter.sol";
import { PendlePTAdapter } from "src/adapters/pendle/PendlePTAdapter.sol";
import { AdapterKind, MakerConfig, SideConfig } from "src/config/MakerConfig.sol";
import { SupercazzolaRouter } from "src/SupercazzolaRouter.sol";
import { YieldArgsBuilder, YIELD_ADJUSTED_RATE_XD } from "src/opcodes/YieldAdjustedRateOpcode.sol";
import { GuardArgsBuilder, CHAINLINK_GUARD_XD } from "src/opcodes/ChainlinkGuardOpcode.sol";
import { CapitalArgsBuilder, MAKER_CAPITAL_GUARD_XD } from "src/opcodes/MakerCapitalGuardOpcode.sol";
import { AggregatorV3Interface } from "src/interfaces/AggregatorV3Interface.sol";
import { BaseChain } from "./BaseChain.s.sol";

address constant BASE_STARGATE_POOL = 0x27a16dc786820B16E5c9028b75B99F6f604b5d26; // StargatePoolUSDC
address constant BASE_STARGATE_STAKING = 0xDFc47DCeF7e8f9Ab19a1b8Af3eeCF000C7ea0B80;
address constant ARB_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
address constant ARB_MARKET = 0x8621c587059357d6C669f72dA3Bfe1398fc0D0B5; // PT-aUSDC-27JUN2024 (EXPIRED)
address constant ARB_ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
address constant ARB_USDC_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
address constant ETH_WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant ETH_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
address constant ETH_MARKET = 0x34280882267ffa6383B363E278B027Be083bBe3b; // PT-wstETH (ACTIVE)
address constant ETH_ORACLE = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
address constant ETH_ETH_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
address constant ETH_USDC_FEED = 0x8ffFf3Ffdd1E2EC7e90A4Cc48ea22fF79C0eEED9;

/// @title AnvilScenario
/// @notice Live scenario runner for the anvil-scripts suite: executes a FULL
///         maker lifecycle (approvals -> capital deployment -> setSides ->
///         ship on Aqua -> fills) against the DEPLOYED stack
///         (deployments/supercazzola-<chain>.json from Deploy.s.sol), with
///         step-by-step logging and final assertions.
///
/// Usage (from anvil-scripts/execute-with-<adapter>.sh):
///   SCENARIO=aave forge script script/AnvilScenario.s.sol \
///     --fork-url http://localhost:8545 --broadcast --skip-simulation
///
/// The maker/taker are the demo's well-known anvil keys; their token balances
/// are seeded by terminal-1-start-configured-anvil.sh.
contract AnvilScenario is Script, StdCheats {
    using SafeERC20 for IERC20;

    string internal _scenario;   // set by the per-adapter scenario scripts (or the SCENARIO env)
    uint256 internal makerKey = vm.envOr("MAKER_KEY", uint256(0xA11CE));
    uint256 internal takerKey = vm.envOr("TAKER_KEY", uint256(0xB0B));
    address internal maker = vm.addr(makerKey);
    address internal taker = vm.addr(takerKey);

    MakerConfig internal makerConfig;
    SupercazzolaRouter internal router;
    IAqua internal aqua;

    function run() external {
        if (bytes(_scenario).length == 0) _scenario = vm.envOr("SCENARIO", string("aave"));
        string memory chain = _chainOf(_scenario);
        string memory path = string.concat("deployments/supercazzola-", chain, ".json");
        string memory artifact = vm.readFile(path);
        address deployedRouter = vm.parseAddress(vm.parseJsonString(artifact, ".router"));
        router = SupercazzolaRouter(payable(deployedRouter));
        makerConfig = MakerConfig(router.MAKER_CONFIG());
        aqua = IAqua(router.AQUA());

        _banner("SCENARIO", _scenario);
        _banner("deployed stack", path);

        if (_eq(_scenario, "aave")) _aave(artifact);
        else if (_eq(_scenario, "erc4626")) _erc4626(artifact);
        else if (_eq(_scenario, "stargate")) _stargate(artifact);
        else if (_eq(_scenario, "pendle-expired")) _pendleExpired();
        else if (_eq(_scenario, "pendle-active")) _pendleActive();
        else revert(string.concat("unknown scenario: ", _scenario));

        _pass();
    }

    // ===================== AAVE (Base) =====================
    AaveV3Adapter internal aaveAdapter;
    address internal weth;
    address internal usdc;
    address internal aWeth;
    address internal aUsdc;
    ISwapVM.Order internal order;
    bytes internal takerTraits;
    uint256 internal fillAmount;

    function _aave(string memory artifact) internal {
        weth = BaseChain.WETH;
        usdc = BaseChain.USDC;
        aWeth = BaseChain.A_WETH;
        aUsdc = BaseChain.A_USDC;

        aaveAdapter = AaveV3Adapter(vm.parseAddress(vm.parseJsonString(artifact, ".AaveV3")));

        vm.startBroadcast(makerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(aWeth).approve(address(router), type(uint256).max); // the router pulls aWETH for the JIT delivery
        IERC20(aUsdc).approve(address(router), type(uint256).max); // the router pulls aUSDC (reverse fills)
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        vm.stopBroadcast();

        // deploy 100% of capital into Aave (transfer + deposit: no allowances)
        uint256 wethReal = 105e18;
        uint256 usdcReal = 262_500e6;
        vm.startBroadcast(makerKey);
        IERC20(weth).transfer(address(aaveAdapter), wethReal);
        aaveAdapter.deposit(maker, weth, wethReal);
        IERC20(usdc).transfer(address(aaveAdapter), usdcReal);
        aaveAdapter.deposit(maker, usdc, usdcReal);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(aaveAdapter), kind: AdapterKind.AaveV3, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(aaveAdapter), kind: AdapterKind.AaveV3, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopBroadcast();
        _logBalances(weth, usdc, aWeth, aUsdc);
        _assertIdleZero(weth, usdc, "capital deployed");

        // ship on Aqua (UNDERLYING units, rate0 = ship-time rates)
        uint256 wethVirtual = IERC20(aWeth).balanceOf(maker) - 1e4;
        uint256 usdcVirtual = IERC20(aUsdc).balanceOf(maker) - 1e4;
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(usdc, weth, aaveAdapter.exchangeRate(usdc), aaveAdapter.exchangeRate(weth)),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(CHAINLINK_GUARD_XD),
                    uint8(92),
                    GuardArgsBuilder.build(
                        weth, usdc, BaseChain.CHAINLINK_ETH_USD, BaseChain.CHAINLINK_USDC_USD, 300, 3600, 86_400
                    ),
                    uint8(36), uint8(20),
                    CapitalArgsBuilder.build(weth)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        vm.startBroadcast(makerKey);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopBroadcast();
        _step("strategy shipped on Aqua - the position is discoverable by anyone");

        bytes memory tt = _takerTraits();
        vm.startBroadcast(takerKey);
        IERC20(usdc).approve(address(router), type(uint256).max);
        (, uint256 quotedOut,) = router.quote(order, usdc, weth, 1000e6, tt);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, 1000e6, tt);
        vm.stopBroadcast();
        _step("FILL 1 - taker sold 1000 USDC, received WETH (Aave JIT delivery)");
        _kv("quote() -> amountOut", quotedOut);
        _kv("swap() -> amountOut", amountOut);
        _assertEq(amountOut, quotedOut, "quote == swap");
        _logBalances(weth, usdc, aWeth, aUsdc);
        _assert(IERC20(weth).balanceOf(taker) == 1e18 + amountOut, "taker received the quoted WETH (seed + fill)");
        _assert(IERC20(weth).balanceOf(maker) == 0, "maker wallet has no idle WETH");

        // reverse fill: taker sells the WETH back, maker re-deploys the USDC
        uint256 wethFromTaker = IERC20(weth).balanceOf(taker);
        vm.startBroadcast(takerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        router.swap(order, weth, usdc, amountOut, tt);
        vm.stopBroadcast();
        _step("FILL 2 (reverse) - taker sold the WETH back, bought USDC");
        _logBalances(weth, usdc, aWeth, aUsdc);
        _assert(IERC20(weth).balanceOf(maker) == 0, "maker wallet has no idle WETH");
        _assert(IERC20(usdc).balanceOf(maker) == 0, "maker wallet has no idle USDC");
        _assert(
            IERC20(aUsdc).balanceOf(maker) > usdcVirtual,
            "maker's USDC side GREW (yield + fees)"
        );
    }

    // ===================== ERC-4626 (Base, Morpho vaults) =====================
    function _erc4626(string memory artifact) internal {
        weth = BaseChain.WETH;
        usdc = BaseChain.USDC;

        ERC4626Adapter adapter = ERC4626Adapter(vm.parseAddress(vm.parseJsonString(artifact, ".ERC4626")));

        vm.startBroadcast(makerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(BaseChain.MORPHO_WETH_VAULT).approve(address(router), type(uint256).max); // JIT delivery pulls
        IERC20(BaseChain.MORPHO_USDC_VAULT).approve(address(router), type(uint256).max);
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(makerKey);
        IERC20(weth).transfer(address(adapter), 105e18);
        adapter.deposit(maker, weth, 105e18);
        IERC20(usdc).transfer(address(adapter), 262_500e6);
        adapter.deposit(maker, usdc, 262_500e6);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(adapter), kind: AdapterKind.ERC4626, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(adapter), kind: AdapterKind.ERC4626, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopBroadcast();
        _banner("capital deployed", "WETH -> Morpho Gauntlet, USDC -> Morpho Steakhouse");
        _logBalances(weth, usdc, BaseChain.MORPHO_WETH_VAULT, BaseChain.MORPHO_USDC_VAULT);

        uint256 wethVirtual = 105e18 - 1e4;
        uint256 usdcVirtual = 262_500e6 - 1e4;
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(usdc, weth, adapter.exchangeRate(usdc), adapter.exchangeRate(weth)),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(CHAINLINK_GUARD_XD),
                    uint8(92),
                    GuardArgsBuilder.build(
                        weth, usdc, BaseChain.CHAINLINK_ETH_USD, BaseChain.CHAINLINK_USDC_USD, 300, 3600, 86_400
                    ),
                    uint8(36), uint8(20),
                    CapitalArgsBuilder.build(weth)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        vm.startBroadcast(makerKey);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopBroadcast();
        _step("strategy shipped on Aqua");

        bytes memory tt = _takerTraits();
        vm.startBroadcast(takerKey);
        IERC20(usdc).approve(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, 1000e6, tt);
        vm.stopBroadcast();
        _step("FILL 1 - taker sold 1000 USDC, received WETH (Morpho JIT)");
        _kv("amountOut", amountOut);
        _logBalances(weth, usdc, BaseChain.MORPHO_WETH_VAULT, BaseChain.MORPHO_USDC_VAULT);
        _assert(IERC20(weth).balanceOf(maker) == 0, "maker wallet has no idle WETH");

        vm.startBroadcast(takerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        router.swap(order, weth, usdc, amountOut, tt);
        vm.stopBroadcast();
        _step("FILL 2 (reverse) - taker sold the WETH back, bought USDC");
        _logBalances(weth, usdc, BaseChain.MORPHO_WETH_VAULT, BaseChain.MORPHO_USDC_VAULT);
        _assert(IERC20(usdc).balanceOf(maker) == 0, "maker wallet has no idle USDC");
        _assert(
            IERC20(BaseChain.MORPHO_USDC_VAULT).balanceOf(maker) > usdcVirtual,
            "maker's USDC side GREW (yield + fees)"
        );
    }

    // ===================== Stargate (Base) =====================
    StargateAdapter internal stargateAdapter;

    function _stargate(string memory artifact) internal {
        weth = BaseChain.WETH;
        usdc = BaseChain.USDC;
        stargateAdapter = StargateAdapter(vm.parseAddress(vm.parseJsonString(artifact, ".Stargate")));
        IERC20 lp = IERC20(stargateAdapter.LP());

        vm.startBroadcast(makerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(makerKey);
        IERC20(usdc).transfer(address(stargateAdapter), 5_000e6);
        stargateAdapter.deposit(maker, usdc, 5_000e6);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(stargateAdapter), kind: AdapterKind.Stargate, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(stargateAdapter), kind: AdapterKind.Stargate, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopBroadcast();
        _banner("capital deployed", "5000 USDC deposited AND staked in Stargate");
        _kv("LP staked", lp.balanceOf(address(stargateAdapter.STAKING())));

        uint256 usdcVirtual = 5_000e6 - 1e4;
        uint256 wethVirtual = 16e17;
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(usdc, weth, 1e18, 1e18),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(36), uint8(20),
                    CapitalArgsBuilder.build(weth)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        vm.startBroadcast(makerKey);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopBroadcast();
        _step("strategy shipped on Aqua");

        bytes memory tt = _takerTraits();
        vm.startBroadcast(takerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, weth, usdc, 0.05e18, tt);
        vm.stopBroadcast();
        _step("FILL - taker sold 0.05 WETH, received USDC (Stargate JIT: unstake -> redeem)");
        _kv("amountOut (USDC)", amountOut);
        _kv("LP still staked", lp.balanceOf(address(stargateAdapter.STAKING())));
        _assert(amountOut >= 120e6 && amountOut <= 180e6, "USDC out is market-shaped (~3125 USDC/WETH)");
    }

    // ===================== Pendle EXPIRED (Arbitrum) =====================
    function _pendleExpired() internal {
        weth = ARB_WETH;
        usdc = ARB_USDC;

        vm.startBroadcast();
        PendlePTAdapter adapter = new PendlePTAdapter(ARB_MARKET, usdc, address(0), address(0), 0);
        vm.stopBroadcast();

        vm.startBroadcast(makerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(adapter.PT()).approve(address(router), type(uint256).max); // the router pulls PT for the JIT delivery
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(makerKey);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopBroadcast();
        _banner("capital", "PT-aUSDC (expired, 1:1 redemption) + WETH passthrough");

        uint256 usdcVirtual = 12_000e6 - 1e4; // = the PT position acquired in fund.sh
        uint256 wethVirtual = 4880e15 - 1e15; // prices WETH at ~2458 USDC (chainlink-aligned)
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(usdc, weth, 1e18, 1e18),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(CHAINLINK_GUARD_XD),
                    uint8(92),
                    GuardArgsBuilder.build(weth, usdc, ARB_ETH_FEED, ARB_USDC_FEED, 300, 3600, 86_400),
                    uint8(36), uint8(20),
                    CapitalArgsBuilder.build(weth)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        vm.startBroadcast(makerKey);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopBroadcast();
        _step("strategy shipped on Aqua");

        bytes memory tt = _takerTraits();
        vm.startBroadcast(takerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, weth, usdc, 0.05e18, tt);
        vm.stopBroadcast();
        _step("FILL - taker sold 0.05 WETH, received USDC (PT -> YT.redeemPY -> SY -> USDC)");
        _kv("amountOut (USDC)", amountOut);
        _kv("maker USDC (revenue, passthrough side)", IERC20(usdc).balanceOf(maker));
        _assert(IERC20(usdc).balanceOf(maker) > 0, "the maker holds the delivered revenue");
    }

    // ===================== Pendle ACTIVE (Ethereum) =====================
    function _pendleActive() internal {
        weth = ETH_WSTETH;
        usdc = ETH_USDC;

        vm.startBroadcast();
        PendlePTAdapter adapter = new PendlePTAdapter(ETH_MARKET, weth, usdc, ETH_ORACLE, 900);
        vm.stopBroadcast();

        vm.startBroadcast(makerKey);
        IERC20(weth).approve(address(router), type(uint256).max);
        IERC20(usdc).approve(address(router), type(uint256).max);
        IERC20(adapter.PT()).approve(address(router), type(uint256).max); // the router pulls PT for the JIT delivery
        IERC20(weth).approve(address(aqua), type(uint256).max);
        IERC20(usdc).approve(address(aqua), type(uint256).max);
        vm.stopBroadcast();

        vm.startBroadcast(makerKey);
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = SideConfig({ underlying: weth, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        sides[1] = SideConfig({ underlying: usdc, adapter: address(adapter), kind: AdapterKind.PendlePT, autoManaged: true });
        makerConfig.setSides(sides);
        vm.stopBroadcast();
        _banner("capital", "PT-wstETH (ACTIVE market, fixed yield) + USDC passthrough");

        uint256 rate0 = adapter.exchangeRate(weth);
        uint256 wethVirtual = 32e18 - 1e15;
        uint256 usdcVirtual = 100_000e6 - 1e4;
        order = MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: maker,
                receiver: address(0),
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: true,
                hasPreTransferOutHook: true,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(router),
                postTransferInData: "",
                preTransferOutTarget: address(router),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: abi.encodePacked(
                    uint8(YIELD_ADJUSTED_RATE_XD),
                    uint8(104),
                    YieldArgsBuilder.build(usdc, weth, 1e18, rate0),
                    uint8(21), uint8(4), FeeArgsBuilder.buildFlatFee(3e6),
                    uint8(17), uint8(0),
                    uint8(36), uint8(20),
                    CapitalArgsBuilder.build(weth)
                )
            })
        );
        address[] memory tokens = new address[](2);
        tokens[0] = weth;
        tokens[1] = usdc;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethVirtual;
        amounts[1] = usdcVirtual;
        vm.startBroadcast(makerKey);
        aqua.ship(address(router), abi.encode(order), tokens, amounts);
        vm.stopBroadcast();
        _step("strategy shipped on Aqua");

        bytes memory tt = _takerTraits();
        deal(usdc, taker, 1000e6);
        vm.startBroadcast(takerKey);
        IERC20(usdc).approve(address(router), type(uint256).max);
        (, uint256 amountOut,) = router.swap(order, usdc, weth, 1000e6, tt);
        vm.stopBroadcast();
        _step("FILL - taker sold 1000 USDC, received wstETH (PT -> market AMM -> SY -> wstETH)");
        _kv("amountOut (wstETH)", amountOut);
        _kv("maker USDC (revenue, passthrough side)", IERC20(usdc).balanceOf(maker));
        _assert(IERC20(usdc).balanceOf(maker) > 0, "the maker holds the delivered revenue");
    }

    // ===================== shared helpers =====================
    function _takerTraits() internal pure returns (bytes memory) {
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(0),
                isExactIn: true,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: true,
                threshold: "",
                to: address(0),
                deadline: 0,
                hasPreTransferInCallback: false,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }

    function _arr2(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _logBalances(address t0, address t1, address y0, address y1) internal view {
        _kv(string.concat("maker idle ", _sym(t0)), IERC20(t0).balanceOf(maker));
        _kv(string.concat("maker idle ", _sym(t1)), IERC20(t1).balanceOf(maker));
        _kv(string.concat("maker ", _sym(y0)), IERC20(y0).balanceOf(maker));
        _kv(string.concat("maker ", _sym(y1)), IERC20(y1).balanceOf(maker));
    }

    function _sym(address t) internal view returns (string memory) {
        (, bytes memory ret) = t.staticcall(abi.encodeWithSignature("symbol()"));
        return ret.length > 0 ? abi.decode(ret, (string)) : "token";
    }

    function _assertIdleZero(address t0, address t1, string memory when) internal view {
        _assert(IERC20(t0).balanceOf(maker) == 0, string.concat("no idle ", _sym(t0), " after ", when));
        _assert(IERC20(t1).balanceOf(maker) == 0, string.concat("no idle ", _sym(t1), " after ", when));
    }

    function _chainOf(string memory scenario) internal pure returns (string memory) {
        if (_eq(scenario, "pendle-expired")) return "arbitrum";
        if (_eq(scenario, "pendle-active")) return "ethereum";
        return "base";
    }

    function artifactPath(string memory chain) internal pure returns (string memory) {
        return string.concat("deployments/supercazzola-", chain, ".json");
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _step(string memory s) internal view {
        console2.log("");
        console2.log(string.concat(">> ", s));
    }

    function _banner(string memory k, string memory v) internal view {
        console2.log(string.concat(">> ", k, ": ", v));
    }

    function _kv(string memory k, uint256 v) internal view {
        console2.log(string.concat("   ", k, ": "), v);
    }

    function _kv(string memory k, string memory v) internal view {
        console2.log(string.concat("   ", k, ": ", v));
    }

    function _assert(bool ok, string memory what) internal pure {
        require(ok, string.concat("SCENARIO ASSERTION FAILED: ", what));
        console2.log(string.concat("   [ok] ", what));
    }

    function _assertEq(uint256 a, uint256 b, string memory what) internal pure {
        _assert(a == b, string.concat(what, " (", vm.toString(a), " vs ", vm.toString(b), ")"));
    }

    function _pass() internal view {
        console2.log("");
        console2.log("SCENARIO PASS");
        console2.log(string.concat("scenario '", _scenario, "' completed successfully on the deployed stack"));
    }

    function _fail() internal pure {
        console2.log("SCENARIO FAIL");
    }
}

import { StdCheats } from "forge-std/StdCheats.sol";
