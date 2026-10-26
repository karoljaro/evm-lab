// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";
import {PoolMath} from "../../contracts/list-02/PoolMath.sol";

contract MathHarness {
    function out(uint256 amountIn, uint256 rIn, uint256 rOut) external pure returns (uint256) {
        return PoolMath.getAmountOut(amountIn, rIn, rOut);
    }
    function input(uint256 output, uint256 rIn, uint256 rOut) external pure returns (uint256) {
        return PoolMath.getAmountIn(output, rIn, rOut);
    }
}

contract PoolMathTest is Test {
    MathHarness private math = new MathHarness();

    function test_FeeGoldenValuesAndIntegerRounding() public view {
        assertEq(math.out(1000, 10_000, 10_000), 906);
        assertEq(math.input(906, 10_000, 10_000), 1000);
        assertEq(math.out(1, 10_000, 10_000), 0);
        assertEq(math.out(1000, 10_000, 20_000), 1813);
    }

    function test_ZeroInputsAndEmptyOrExhaustedReserves() public {
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        math.out(0, 10_000, 10_000);
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        math.input(0, 10_000, 10_000);
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        math.out(1, 0, 10_000);
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        math.out(1, 10_000, 0);
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        math.input(10_000, 10_000, 10_000);
    }

    function test_ReserveCapPreventsMultiplicationOverflow() public {
        uint256 maximum = type(uint112).max;
        assertLt(math.out(maximum, maximum, maximum), maximum);
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        math.out(maximum + 1, maximum, maximum);
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        math.input(1, maximum + 1, maximum);
    }

    function testFuzz_QuoteInputIsSufficientAndOneLessIsNot(uint96 raw) public view {
        uint256 desired = bound(uint256(raw), 1, 99 ether);
        uint256 input = math.input(desired, 100 ether, 100 ether);
        assertGe(math.out(input, 100 ether, 100 ether), desired);
        // The v2 +1 convention can overpay by 1 only if the division was exact.
        uint256 numerator = uint256(100 ether) * desired * 1000;
        uint256 denominator = (100 ether - desired) * 997;
        if (numerator % denominator != 0) assertLt(math.out(input - 1, 100 ether, 100 ether), desired);
    }
}
