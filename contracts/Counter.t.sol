// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test, stdError} from "forge-std/Test.sol";
import {Counter} from "./Counter.sol";

contract CounterTest is Test {
    Counter counter;

    function setUp() public {
        counter = new Counter();
    }

    function test_InitialValueIsZero() public view {
        assertEq(counter.value(), 0);
    }

    function test_IncrementsAccumulate() public {
        counter.inc();
        counter.incBy(5);

        assertEq(counter.value(), 6);
    }

    function test_ZeroIncrementReverts() public {
        vm.expectRevert(Counter.ZeroIncrement.selector);
        counter.incBy(0);

        assertEq(counter.value(), 0);
    }

    function test_OverflowReverts() public {
        counter.incBy(type(uint256).max);

        vm.expectRevert(stdError.arithmeticError);
        counter.inc();

        assertEq(counter.value(), type(uint256).max);
    }

    function testFuzz_IncrementBy(uint128 amount) public {
        vm.assume(amount > 0);
        counter.incBy(amount);

        assertEq(counter.value(), uint256(amount));
    }
}
