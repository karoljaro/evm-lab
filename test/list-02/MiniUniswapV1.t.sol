// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {PoolFixture, EthReceiver, LabToken, NoReturnToken, MiniUniswapV1, PoolMath, PoolShares, SafeERC20, ReentrancyGuard} from "./helpers/PoolFixture.sol";

contract MiniUniswapV1Test is PoolFixture {
    function test_InitialLiquidityAndLockedShares() public {
        (uint256 tokens, uint256 shares) = v1a.addLiquidity{value: R}(R, R - 1000, D);
        assertEq(tokens, R);
        assertEq(shares, R - 1000);
        assertEq(v1a.balanceOf(address(this)), shares);
        assertEq(v1a.balanceOf(address(v1a)), 1000);
        assertEq(v1a.totalSupply(), R);
        _assertV1Reserves();
    }

    function test_ProportionalDepositPullsOnlyRequiredTokens() public {
        _seedV1();
        a.mint(ALICE, 30 ether);
        vm.startPrank(ALICE);
        a.approve(address(v1a), D);
        (uint256 tokens, uint256 shares) = v1a.addLiquidity{value: 10 ether}(30 ether, 10 ether, D);
        vm.stopPrank();
        assertEq(tokens, 10 ether);
        assertEq(shares, 10 ether);
        assertEq(a.balanceOf(ALICE), 20 ether);
        assertEq(v1a.balanceOf(ALICE), 10 ether);
        _assertV1Reserves();
    }

    function test_DepositRoundsTokensUpAndSharesDown() public {
        v1a.addLiquidity{value: 3 ether}(10 ether, 0, D);
        (uint256 tokens,) = v1a.addLiquidity{value: 1}(4, 0, D);
        assertEq(tokens, 4);
        _assertV1Reserves();
    }

    function test_TransferableLpAndProportionalWithdrawal() public {
        _seedV1();
        v1a.transfer(ALICE, 10 ether);
        uint256 beforeEth = ALICE.balance;
        vm.prank(ALICE);
        (uint256 tokens, uint256 eth) = v1a.removeLiquidity(10 ether, 10 ether, 10 ether, payable(ALICE), D);
        assertEq(tokens, 10 ether);
        assertEq(eth, 10 ether);
        assertEq(ALICE.balance - beforeEth, eth);
        assertEq(a.balanceOf(ALICE), tokens);
        assertEq(v1a.balanceOf(ALICE), 0);
        _assertV1Reserves();
    }

    function test_WithdrawAllUserSharesLeavesMinimumLiquidity() public {
        _seedV1();
        v1a.removeLiquidity(R - 1000, 0, 0, payable(address(this)), D);
        assertEq(v1a.totalSupply(), 1000);
        assertEq(a.balanceOf(address(v1a)), 1000);
        assertEq(address(v1a).balance, 1000);
        _assertV1Reserves();
    }

    function test_EthToTokenUses997AndRetainsFee() public {
        _seedV1();
        uint256 expected = 10 ether * 997 * R / (R * 1000 + 10 ether * 997);
        uint256 out = v1a.ethToTokenSwap{value: 10 ether}(expected, BOB, D);
        assertEq(out, expected);
        assertEq(a.balanceOf(BOB), expected);
        assertGt(a.balanceOf(address(v1a)) * address(v1a).balance, R * R);
        assertLt(out, 10 ether * R / (R + 10 ether));
        _assertV1Reserves();
    }

    function test_TokenToEthUses997AndRetainsFee() public {
        _seedV1();
        uint256 expected = 10 ether * 997 * R / (R * 1000 + 10 ether * 997);
        uint256 out = v1a.tokenToEthSwap(10 ether, expected, payable(BOB), D);
        assertEq(out, expected);
        assertEq(BOB.balance, expected);
        assertGt(a.balanceOf(address(v1a)) * address(v1a).balance, R * R);
        _assertV1Reserves();
    }

    function test_SwapSlippageRevertsBalancesAtomically() public {
        _seedV1();
        uint256 userTokens = a.balanceOf(address(this));
        uint256 userEth = address(this).balance;
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.ethToTokenSwap{value: 10 ether}(10 ether, BOB, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.tokenToEthSwap(10 ether, 10 ether, payable(BOB), D);
        assertEq(a.balanceOf(address(this)), userTokens);
        assertEq(address(this).balance, userEth);
        _assertV1Reserves();
    }

    function test_DepositSlippageAndMinShares() public {
        _seedV1();
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.addLiquidity{value: 10 ether}(9 ether, 0, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.addLiquidity{value: 10 ether}(10 ether, 10 ether + 1, D);
        _assertV1Reserves();
    }

    function test_WithdrawalSlippageBothAssets() public {
        _seedV1();
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.removeLiquidity(10 ether, 10 ether + 1, 0, payable(BOB), D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.removeLiquidity(10 ether, 0, 10 ether + 1, payable(BOB), D);
        assertEq(v1a.balanceOf(address(this)), R - 1000);
    }

    function test_AllEntryPointsEnforceDeadline() public {
        _seedV1();
        vm.warp(100);
        vm.expectRevert(PoolShares.Expired.selector);
        v1a.addLiquidity{value: 1 ether}(1 ether, 0, 99);
        vm.expectRevert(PoolShares.Expired.selector);
        v1a.removeLiquidity(1 ether, 0, 0, payable(BOB), 99);
        vm.expectRevert(PoolShares.Expired.selector);
        v1a.ethToTokenSwap{value: 1 ether}(0, BOB, 99);
        vm.expectRevert(PoolShares.Expired.selector);
        v1a.tokenToEthSwap(1 ether, 0, payable(BOB), 99);
        v1a.ethToTokenSwap{value: 1 ether}(0, BOB, 100); // equality is allowed
    }

    function test_ZeroInputsAndTooSmallInitialDeposit() public {
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        v1a.addLiquidity(1 ether, 0, D);
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        v1a.addLiquidity{value: 1 ether}(0, 0, D);
        vm.expectRevert(PoolShares.ZeroLiquidity.selector);
        v1a.addLiquidity{value: 1000}(1000, 0, D);
        _seedV1();
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        v1a.ethToTokenSwap(0, BOB, D);
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        v1a.tokenToEthSwap(0, 0, payable(BOB), D);
        vm.expectRevert(PoolShares.ZeroLiquidity.selector);
        v1a.removeLiquidity(0, 0, 0, payable(BOB), D);
    }

    function test_EmptyPoolAndOutputRoundedToZero() public {
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        v1a.ethToTokenSwap{value: 1 ether}(0, BOB, D);
        vm.expectRevert(PoolShares.ZeroLiquidity.selector);
        v1a.removeLiquidity(1, 0, 0, payable(BOB), D);
        v1a.addLiquidity{value: R}(1 ether, 0, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v1a.ethToTokenSwap{value: 1}(0, BOB, D);
    }

    function test_InsufficientBalanceAllowanceAndLp() public {
        _seedV1();
        a.approve(address(v1a), 0);
        vm.expectRevert();
        v1a.tokenToEthSwap(1 ether, 0, payable(BOB), D);
        vm.startPrank(ALICE);
        a.approve(address(v1a), D);
        vm.expectRevert();
        v1a.tokenToEthSwap(1 ether, 0, payable(BOB), D);
        vm.expectRevert();
        v1a.removeLiquidity(1 ether, 0, 0, payable(BOB), D);
        vm.stopPrank();
        _assertV1Reserves();
    }

    function test_FalseReturnTokenRevertsOnInputAndOutput() public {
        _seedV1();
        a.setFailTransfers(true);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(a)));
        v1a.tokenToEthSwap(1 ether, 0, payable(BOB), D);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(a)));
        v1a.ethToTokenSwap{value: 1 ether}(0, BOB, D);
        _assertV1Reserves();
    }

    function test_NoReturnTokenIsSupported() public {
        NoReturnToken token = new NoReturnToken();
        MiniUniswapV1 pool = new MiniUniswapV1(address(token));
        token.mint(address(this), 200 ether);
        token.approve(address(pool), D);
        pool.addLiquidity{value: R}(R, 0, D);
        pool.ethToTokenSwap{value: 1 ether}(0, BOB, D);
        pool.tokenToEthSwap(1 ether, 0, payable(BOB), D);
        pool.removeLiquidity(1 ether, 0, 0, payable(BOB), D);
        assertGt(token.balanceOf(BOB), 0);
    }

    function test_TaxedInputRejectedOnDepositAndSwap() public {
        a.setTaxTransfers(true);
        vm.expectRevert(PoolShares.UnsupportedToken.selector);
        v1a.addLiquidity{value: R}(R, 0, D);
        a.setTaxTransfers(false);
        _seedV1();
        a.setTaxTransfers(true);
        vm.expectRevert(PoolShares.UnsupportedToken.selector);
        v1a.tokenToEthSwap(1 ether, 0, payable(BOB), D);
        _assertV1Reserves();
    }

    function test_EthReceiverRevertRollsBackTokenTransferAndBurn() public {
        _seedV1();
        EthReceiver receiver = new EthReceiver(v1a);
        receiver.configure(true, false, false);
        uint256 beforeTokens = a.balanceOf(address(this));
        vm.expectRevert(MiniUniswapV1.EthTransferFailed.selector);
        v1a.tokenToEthSwap(1 ether, 0, payable(address(receiver)), D);
        vm.expectRevert(MiniUniswapV1.EthTransferFailed.selector);
        v1a.removeLiquidity(1 ether, 0, 0, payable(address(receiver)), D);
        assertEq(a.balanceOf(address(this)), beforeTokens);
        assertEq(a.balanceOf(address(receiver)), 0);
        assertEq(v1a.balanceOf(address(this)), R - 1000);
        _assertV1Reserves();
    }

    function test_EthReentrancyBlockedEvenWhenCaught() public {
        _seedV1();
        EthReceiver receiver = new EthReceiver(v1a);
        receiver.configure(false, true, true);
        v1a.tokenToEthSwap(1 ether, 0, payable(address(receiver)), D);
        assertTrue(receiver.blocked());
        _assertV1Reserves();
        receiver.configure(false, true, false);
        vm.expectRevert(MiniUniswapV1.EthTransferFailed.selector);
        v1a.removeLiquidity(1 ether, 0, 0, payable(address(receiver)), D);
    }

    function test_TokenHookCannotReenterDepositOrSwap() public {
        a.setHook(address(v1a), abi.encodeCall(v1a.sync, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        v1a.addLiquidity{value: R}(R, 0, D);
        a.setHook(address(0), "");
        _seedV1();
        a.setHook(address(v1a), abi.encodeCall(v1a.sync, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        v1a.ethToTokenSwap{value: 1 ether}(0, BOB, D);
        _assertV1Reserves();
    }

    function test_DonationsSyncAndLiveBalancePricing() public {
        _seedV1();
        a.transfer(address(v1a), 10 ether);
        vm.deal(address(v1a), R + 10 ether); // forced ETH, not a normal payable deposit
        (uint112 oldToken,) = v1a.getReserves();
        assertEq(oldToken, R);
        v1a.sync();
        _assertV1Reserves();
        a.transfer(address(v1a), 10 ether);
        uint256 expected = uint256(1 ether) * 997 * 120 ether / (110 ether * 1000 + 1 ether * 997);
        assertEq(v1a.ethToTokenSwap{value: 1 ether}(expected, BOB, D), expected);
        _assertV1Reserves();
    }

    function test_ReserveOverflowAndInvalidAddresses() public {
        vm.expectRevert(PoolShares.InvalidToken.selector);
        new MiniUniswapV1(address(0));
        vm.expectRevert(PoolShares.InvalidToken.selector);
        new MiniUniswapV1(ALICE);
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        v1a.addLiquidity{value: 1 ether}(uint256(type(uint112).max) + 1, 0, D);
        _seedV1();
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v1a.ethToTokenSwap{value: 1 ether}(0, address(a), D);
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v1a.ethToTokenSwap{value: 1 ether}(0, address(v1a), D);
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v1a.tokenToEthSwap(1 ether, 0, payable(address(0)), D);
        a.mint(address(v1a), uint256(type(uint112).max));
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        v1a.sync();
    }

    function testFuzz_BothSwapDirectionsPreserveK(uint96 raw) public {
        _seedV1();
        uint256 input = bound(uint256(raw), 1000, 50 ether);
        uint256 expected = input * 997 * R / (R * 1000 + input * 997);
        assertEq(v1a.ethToTokenSwap{value: input}(expected, BOB, D), expected);
        (uint112 rt, uint112 re) = v1a.getReserves();
        assertGe(uint256(rt) * re, R * R);
        uint256 k = uint256(rt) * re;
        expected = input * 997 * uint256(re) / (uint256(rt) * 1000 + input * 997);
        assertEq(v1a.tokenToEthSwap(input, expected, payable(BOB), D), expected);
        (rt, re) = v1a.getReserves();
        assertGe(uint256(rt) * re, k);
        _assertV1Reserves();
    }

    function testFuzz_DepositWithdrawalCannotCreateValue(uint96 raw) public {
        _seedV1();
        uint256 amount = bound(uint256(raw), 1_000_000, 50 ether);
        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v1a), D);
        (, uint256 shares) = v1a.addLiquidity{value: amount}(amount, 0, D);
        (uint256 tokens, uint256 eth) = v1a.removeLiquidity(shares, 0, 0, payable(ALICE), D);
        vm.stopPrank();
        assertLe(tokens, amount);
        assertLe(eth, amount);
        assertEq(v1a.balanceOf(ALICE), 0);
        _assertV1Reserves();
    }
}
