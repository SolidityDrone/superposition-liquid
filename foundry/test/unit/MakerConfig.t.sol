// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Test } from "forge-std/Test.sol";

import { MockAavePool, MockAToken } from "test/unit/mocks/MockAavePool.sol";
import { MockToken } from "test/unit/mocks/MockToken.sol";
import { AaveV3Adapter } from "src/adapters/AaveV3Adapter.sol";
import { AdapterKind, MakerConfig, SideConfig, SideSet } from "src/config/MakerConfig.sol";

contract MakerConfigTest is Test {
    MakerConfig internal makerConfig;
    MockAavePool internal pool;
    AaveV3Adapter internal adapterAave;
    AaveV3Adapter internal adapterAave2;
    MockToken internal usdc;
    MockToken internal weth;

    address internal maker = makeAddr("maker");
    address internal eoa = makeAddr("codeless");

    function _side(address underlying, address adapter, AdapterKind kind, bool autoManaged)
        internal
        pure
        returns (SideConfig memory)
    {
        return SideConfig({ underlying: underlying, adapter: adapter, kind: kind, autoManaged: autoManaged });
    }

    function setUp() public {
        makerConfig = new MakerConfig();
        pool = new MockAavePool();
        usdc = new MockToken("USDC", 6);
        weth = new MockToken("WETH", 18);
        pool.registerAToken(address(usdc), new MockAToken());
        pool.registerAToken(address(weth), new MockAToken());
        adapterAave = new AaveV3Adapter(address(pool), address(0));
        adapterAave2 = new AaveV3Adapter(address(pool), address(0));
    }

    function test_setSides_storesSidePerToken() public {
        SideConfig[] memory sides = new SideConfig[](2);
        sides[0] = _side(address(weth), address(adapterAave), AdapterKind.AaveV3, true);
        sides[1] = _side(address(usdc), address(adapterAave2), AdapterKind.AaveV3, true);

        vm.prank(maker);
        makerConfig.setSides(sides);

        assertEq(makerConfig.sides(maker, address(weth)).adapter, address(adapterAave));
        assertEq(makerConfig.sides(maker, address(usdc)).adapter, address(adapterAave2));
        assertTrue(makerConfig.sides(maker, address(weth)).autoManaged);
        assertEq(
            uint8(makerConfig.sides(maker, address(weth)).kind),
            uint8(AdapterKind.AaveV3)
        );
    }

    function test_setSides_overwritesPerToken() public {
        SideConfig[] memory first = new SideConfig[](1);
        first[0] = _side(address(usdc), address(adapterAave), AdapterKind.AaveV3, true);
        vm.prank(maker);
        makerConfig.setSides(first);

        SideConfig[] memory second = new SideConfig[](1);
        second[0] = _side(address(usdc), address(adapterAave2), AdapterKind.AaveV3, false);
        vm.prank(maker);
        makerConfig.setSides(second);

        assertEq(makerConfig.sides(maker, address(usdc)).adapter, address(adapterAave2));
        assertFalse(makerConfig.sides(maker, address(usdc)).autoManaged);
    }

    function test_sides_returnsEmptyForUnknownMakerOrToken() public {
        SideConfig memory s = makerConfig.sides(maker, address(weth));
        assertEq(s.adapter, address(0));
        assertFalse(s.autoManaged);

        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(weth), address(adapterAave), AdapterKind.AaveV3, true);
        vm.prank(maker);
        makerConfig.setSides(sides);

        // other token untouched, read permissionless from anyone
        vm.prank(makeAddr("anyone"));
        assertEq(makerConfig.sides(maker, address(usdc)).adapter, address(0));
    }

    function test_setSides_emitsSideSet() public {
        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(weth), address(adapterAave), AdapterKind.AaveV3, true);

        vm.prank(maker);
        vm.expectEmit(true, true, true, true, address(makerConfig));
        emit SideSet(maker, address(weth), address(adapterAave), AdapterKind.AaveV3, true);
        makerConfig.setSides(sides);
    }

    function test_setSides_revertsZeroUnderlying() public {
        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(0), address(adapterAave), AdapterKind.AaveV3, true);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSignature("InvalidSide()"));
        makerConfig.setSides(sides);
    }

    function test_setSides_revertsZeroAdapter() public {
        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(weth), address(0), AdapterKind.AaveV3, true);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSignature("InvalidSide()"));
        makerConfig.setSides(sides);
    }

    function test_setSides_revertsKindNone() public {
        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(weth), address(adapterAave), AdapterKind.None, true);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSignature("InvalidSide()"));
        makerConfig.setSides(sides);
    }

    function test_setSides_revertsCodelessAdapter() public {
        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(weth), eoa, AdapterKind.AaveV3, true);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSignature("AdapterInvalid()"));
        makerConfig.setSides(sides);
    }

    function test_setSides_revertsAdapterWithoutName() public {
        // a contract with code but no name() fails validation
        Nameless target = new Nameless();
        SideConfig[] memory sides = new SideConfig[](1);
        sides[0] = _side(address(weth), address(target), AdapterKind.AaveV3, true);
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSignature("AdapterInvalid()"));
        makerConfig.setSides(sides);
    }
}

contract Nameless {
    uint256 public x;
}
