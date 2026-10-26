// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {PoolFixture, MiniUniswapV2, PoolMath, ReentrancyGuard} from "./helpers/PoolFixture.sol";
import {FlashBorrower} from "./helpers/FlashBorrower.sol";
import {FlashArbitrage} from "../../contracts/list-02/examples/FlashArbitrage.sol";

contract FlashSwapTest is PoolFixture {
    FlashBorrower private borrower;
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);

    function setUp() public override {
        super.setUp();
        _seedV2();
        borrower = new FlashBorrower(v2);
    }

    function _fundFees(uint256 out0, uint256 out1) private {
        if (out0 != 0) a.mint(address(borrower), borrower.debt(out0) - out0);
        if (out1 != 0) b.mint(address(borrower), borrower.debt(out1) - out1);
    }

    function test_OptimisticTransferAndExactSameTokenRepayment() public {
        uint256 out = 10 ether;
        uint256 debt = borrower.debt(out);
        _fundFees(out, 0);
        vm.expectEmit(true, true, false, true, address(v2));
        emit Swap(address(borrower), debt, 0, out, 0, address(borrower));
        borrower.run(out, 0, FlashBorrower.Mode.Repay);
        assertEq(borrower.seen0(), debt); // borrowed tokens present BEFORE final K verification
        assertEq(a.balanceOf(address(borrower)), 0);
        assertEq(a.balanceOf(address(v2)), R + debt - out);
        assertEq(b.balanceOf(address(v2)), R);
        assertGt(a.balanceOf(address(v2)) * b.balanceOf(address(v2)), R * R);
        _assertV2Reserves();
    }

    function test_FlashToken1AndBothOutputsInferBothInputs() public {
        _fundFees(0, 5 ether);
        borrower.run(0, 5 ether, FlashBorrower.Mode.Repay);
        assertEq(borrower.seen1(), borrower.debt(5 ether));
        _fundFees(3 ether, 7 ether);
        uint256 debt0 = borrower.debt(3 ether);
        uint256 debt1 = borrower.debt(7 ether);
        vm.expectEmit(true, true, false, true, address(v2));
        emit Swap(address(borrower), debt0, debt1, 3 ether, 7 ether, address(borrower));
        borrower.run(3 ether, 7 ether, FlashBorrower.Mode.Repay);
        _assertV2Reserves();
    }

    function test_RepaymentInOtherToken() public {
        uint256 repayment = uint256(100 ether) * 10 ether * 1000 / ((100 ether - 10 ether) * 997) + 1;
        b.mint(address(borrower), repayment);
        vm.expectEmit(true, true, false, true, address(v2));
        emit Swap(address(borrower), 0, repayment, 10 ether, 0, address(borrower));
        borrower.run(10 ether, 0, FlashBorrower.Mode.OtherToken);
        assertEq(a.balanceOf(address(borrower)), 10 ether);
        assertEq(b.balanceOf(address(borrower)), 0);
        _assertV2Reserves();
    }

    function test_OneWeiUnderpaymentRevertsEveryTransfer() public {
        _fundFees(10 ether, 0);
        uint256 feeBefore = a.balanceOf(address(borrower));
        vm.expectRevert(MiniUniswapV2.InvariantK.selector);
        borrower.run(10 ether, 0, FlashBorrower.Mode.Underpay);
        assertEq(a.balanceOf(address(v2)), R);
        assertEq(a.balanceOf(address(borrower)), feeBefore);
        assertEq(borrower.seen0(), 0); // callback writes reverted too
        _assertV2Reserves();
    }

    function test_NoRepaymentFailsInputCheck() public {
        vm.expectRevert(MiniUniswapV2.InsufficientInput.selector);
        borrower.run(10 ether, 0, FlashBorrower.Mode.NoRepay);
        assertEq(a.balanceOf(address(borrower)), 0);
        _assertV2Reserves();
    }

    function test_NoFeeFundingAndCallbackFailureAreAtomic() public {
        vm.expectRevert(); // borrower owns the principal but cannot pay the additional fee
        borrower.run(10 ether, 0, FlashBorrower.Mode.Repay);
        vm.expectRevert(FlashBorrower.CallbackFailed.selector);
        borrower.run(10 ether, 0, FlashBorrower.Mode.Fail);
        assertEq(a.balanceOf(address(borrower)), 0);
        _assertV2Reserves();
    }

    function test_MaliciousCallbackCannotReenterAnyReserveMutation() public {
        for (uint256 mode = uint256(FlashBorrower.Mode.ReenterSwap); mode <= uint256(FlashBorrower.Mode.ReenterSync); ++mode) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            borrower.run(10 ether, 0, FlashBorrower.Mode(mode));
            assertEq(a.balanceOf(address(borrower)), 0);
            _assertV2Reserves();
        }
    }

    function test_CaughtReentrancyStillRequiresFullRepayment() public {
        _fundFees(10 ether, 0);
        borrower.run(10 ether, 0, FlashBorrower.Mode.CatchReentry);
        assertTrue(borrower.blocked());
        _assertV2Reserves();
    }

    function test_OverflowInsideCallbackRevertsMintAndBorrow() public {
        uint256 supply = a.totalSupply();
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        borrower.run(10 ether, 0, FlashBorrower.Mode.Overflow);
        assertEq(a.totalSupply(), supply);
        assertEq(a.balanceOf(address(borrower)), 0);
        _assertV2Reserves();
    }

    function _arbitrage(bool profitable) private returns (FlashArbitrage arb, MiniUniswapV2 market) {
        market = new MiniUniswapV2(address(a), address(b));
        a.approve(address(market), D);
        b.approve(address(market), D);
        market.addLiquidity(100 ether, profitable ? 200 ether : 100 ether, 0, 0, 0, D);
        arb = new FlashArbitrage(v2, market);
    }

    function test_ArbitrageStartsWithZeroTokensAndPaysProfit() public {
        (FlashArbitrage arb, MiniUniswapV2 market) = _arbitrage(true);
        assertEq(a.balanceOf(address(arb)), 0);
        assertEq(b.balanceOf(address(arb)), 0);
        uint256 proceeds = uint256(10 ether) * 997 * 200 ether / (100 ether * 1000 + 10 ether * 997);
        uint256 repayment = uint256(100 ether) * 10 ether * 1000 / (90 ether * 997) + 1;
        uint256 beforeB = b.balanceOf(address(this));
        arb.execute(10 ether, 1 ether, D);
        assertEq(b.balanceOf(address(this)) - beforeB, proceeds - repayment);
        assertEq(a.balanceOf(address(arb)), 0);
        assertEq(b.balanceOf(address(arb)), 0);
        (uint112 market0, uint112 market1) = market.getReserves();
        assertGt(uint256(market0) * market1, 100 ether * 200 ether);
        _assertV2Reserves();
    }

    function test_UnprofitableArbitrageRevertsBothMarkets() public {
        (FlashArbitrage arb, MiniUniswapV2 market) = _arbitrage(false);
        vm.expectRevert(FlashArbitrage.NotProfitable.selector);
        arb.execute(10 ether, 0, D);
        assertEq(a.balanceOf(address(market)), R);
        assertEq(b.balanceOf(address(market)), R);
        assertEq(a.balanceOf(address(arb)), 0);
        _assertV2Reserves();
    }

    function test_ArbitrageMinProfitAndDeadline() public {
        (FlashArbitrage arb,) = _arbitrage(true);
        vm.expectRevert(FlashArbitrage.NotProfitable.selector);
        arb.execute(10 ether, 100 ether, D);
        vm.warp(100);
        vm.expectRevert(FlashArbitrage.Expired.selector);
        arb.execute(10 ether, 0, 99);
        _assertV2Reserves();
    }

    function test_ForgedCallbacksAndThirdPartyExecutionRejected() public {
        (FlashArbitrage arb,) = _arbitrage(true);
        vm.expectRevert(FlashArbitrage.Unauthorized.selector);
        arb.miniUniswapV2Call(address(arb), 1 ether, 0, abi.encode(0, D));
        vm.prank(address(v2)); // even correct msg.sender is insufficient without an active loan
        vm.expectRevert(FlashArbitrage.Unauthorized.selector);
        arb.miniUniswapV2Call(address(arb), 1 ether, 0, abi.encode(0, D));
        vm.prank(ALICE);
        vm.expectRevert(FlashArbitrage.Unauthorized.selector);
        arb.execute(1 ether, 0, D);
        vm.expectRevert(FlashArbitrage.InvalidMarket.selector);
        new FlashArbitrage(v2, v2);
    }

    function testFuzz_MinimumFlashRepayment(uint96 raw) public {
        uint256 out = bound(uint256(raw), 1, 99 ether);
        uint256 debt = (out * 1000 + 996) / 997;
        a.mint(address(borrower), debt - out);
        borrower.run(out, 0, FlashBorrower.Mode.Repay);
        assertEq(a.balanceOf(address(v2)), R + debt - out);
        assertGe((a.balanceOf(address(v2)) * 1000 - debt * 3) * R * 1000, R * R * 1_000_000);
        assertEq(a.balanceOf(address(borrower)), 0);
        _assertV2Reserves();
    }
}
