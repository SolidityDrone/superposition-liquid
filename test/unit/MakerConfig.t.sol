// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { MakerConfig, MakerVaultConfig } from "src/config/MakerConfig.sol";

contract MakerConfigTest is Test {
    MakerConfig internal makerConfig;

    address internal maker = makeAddr("maker");
    address internal adapter = makeAddr("adapter");
    address internal usdc = makeAddr("usdc");
    address internal weth = makeAddr("weth");

    function _defaultConfig() internal view returns (MakerVaultConfig memory) {
        return MakerVaultConfig({
            adapter: adapter,
            underlyingIn: usdc,
            underlyingOut: weth,
            autoDepositIn: true,
            autoWithdrawOut: true
        });
    }

    function setUp() public {
        makerConfig = new MakerConfig();
    }

    function test_setConfig_storesConfigForMsgSender() public {
        MakerVaultConfig memory cfg = _defaultConfig();

        vm.prank(maker);
        makerConfig.setConfig(cfg);

        MakerVaultConfig memory stored = makerConfig.getConfig(maker);
        assertEq(stored.adapter, adapter);
        assertEq(stored.underlyingIn, usdc);
        assertEq(stored.underlyingOut, weth);
        assertTrue(stored.autoDepositIn);
        assertTrue(stored.autoWithdrawOut);
    }

    function test_setConfig_revertsForZeroAdapter() public {
        MakerVaultConfig memory cfg = _defaultConfig();
        cfg.adapter = address(0);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSignature("AdapterZero()"));
        makerConfig.setConfig(cfg);
    }

    function test_getConfig_returnsEmptyForUnknownMaker() public {
        MakerVaultConfig memory stored = makerConfig.getConfig(makeAddr("unknown"));
        assertEq(stored.adapter, address(0));
    }

    function test_setConfig_overwritesPreviousConfig() public {
        vm.startPrank(maker);
        makerConfig.setConfig(_defaultConfig());

        MakerVaultConfig memory cfg2 = _defaultConfig();
        cfg2.autoWithdrawOut = false;
        makerConfig.setConfig(cfg2);
        vm.stopPrank();

        assertFalse(makerConfig.getConfig(maker).autoWithdrawOut);
    }

    function test_getConfig_isPermissionlessRead() public {
        vm.prank(maker);
        makerConfig.setConfig(_defaultConfig());

        vm.prank(makeAddr("anyone"));
        assertEq(makerConfig.getConfig(maker).adapter, adapter);
    }
}
