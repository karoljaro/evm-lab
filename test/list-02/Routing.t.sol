// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {PoolFixture, MiniRouter, PoolShares, PoolMath} from "./helpers/PoolFixture.sol";

contract RoutingTest is PoolFixture {
    function setUp() public override {
        super.setUp();
        _seedV1();
        v1b.addLiquidity{value: R}(R, 0, D);
        _seedV2();
    }

    function test_V1TokenEthTokenUsesTwoSeparatePoolsAtomically() public {
        uint256 intermediate = PoolMath.getAmountOut(1 ether, R, R);
        uint256 expected = PoolMath.getAmountOut(intermediate, R, R);
        uint256 actual = router.swapV1ToV1(v1a, v1b, 1 ether, intermediate, expected, BOB, D);
        assertEq(actual, expected);
        assertEq(b.balanceOf(BOB), expected);
        assertEq(a.balanceOf(address(router)), 0);
        assertEq(b.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
        assertEq(a.allowance(address(router), address(v1a)), 0);
        assertGt(a.balanceOf(address(v1a)) * address(v1a).balance, R * R);
        assertGt(b.balanceOf(address(v1b)) * address(v1b).balance, R * R);
        _assertV1Reserves();
    }

    function test_V1FinalSlippageRollsBackBothHopsAndApproval() public {
        uint256 beforeTokens = a.balanceOf(address(this));
        vm.expectRevert(PoolShares.Slippage.selector);
        router.swapV1ToV1(v1a, v1b, 1 ether, 0, 1 ether, BOB, D);
        assertEq(a.balanceOf(address(this)), beforeTokens);
        assertEq(a.balanceOf(address(v1a)), R);
        assertEq(b.balanceOf(address(v1b)), R);
        assertEq(address(v1a).balance, R);
        assertEq(address(v1b).balance, R);
        assertEq(a.allowance(address(router), address(v1a)), 0);
        assertEq(b.balanceOf(BOB), 0);
        _assertV1Reserves();
    }

    function test_V1IntermediateSlippageAndDeadline() public {
        vm.expectRevert(PoolShares.Slippage.selector);
        router.swapV1ToV1(v1a, v1b, 1 ether, 1 ether, 0, BOB, D);
        vm.warp(100);
        vm.expectRevert(MiniRouter.Expired.selector);
        router.swapV1ToV1(v1a, v1b, 1 ether, 0, 0, BOB, 99);
    }

    function test_V1InvalidRouteAndInsufficientFunds() public {
        vm.expectRevert(MiniRouter.InvalidRoute.selector);
        router.swapV1ToV1(v1a, v1a, 1 ether, 0, 0, BOB, D);
        vm.prank(ALICE);
        vm.expectRevert();
        router.swapV1ToV1(v1a, v1b, 1 ether, 0, 0, BOB, D);
    }

    function test_V2RouterSupportsReverseDirectionAndMinimumOutput() public {
        uint256 expected = PoolMath.getAmountOut(1 ether, R, R);
        assertEq(router.swapV2(v2, false, 1 ether, expected, BOB, D), expected);
        assertEq(a.balanceOf(BOB), expected);
        assertEq(b.balanceOf(address(router)), 0);
        _assertV2Reserves();
    }
}
