// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {PoolFixture, AtomicSwap, MiniUniswapV2, PoolShares, PoolMath, LabToken, NoReturnToken, SafeERC20, ReentrancyGuard} from "./helpers/PoolFixture.sol";
import {MiniRouter} from "../../contracts/list-02/MiniRouter.sol";

contract MiniUniswapV2Test is PoolFixture {
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);

    function test_InitialLiquidityAndLpShares() public {
        (uint256 amount0, uint256 amount1, uint256 shares) = v2.addLiquidity(R, R, R, R, R - 1000, D);
        assertEq(amount0, R);
        assertEq(amount1, R);
        assertEq(shares, R - 1000);
        assertEq(v2.totalSupply(), R);
        assertEq(v2.balanceOf(address(v2)), 1000);
        assertEq(v2.balanceOf(address(this)), shares);
        _assertV2Reserves();
    }

    function test_InitialAsymmetricLiquidityUsesGeometricMean() public {
        (,, uint256 shares) = v2.addLiquidity(25 ether, 100 ether, 0, 0, 0, D);
        assertEq(shares, 50 ether - 1000);
    }

    function test_SubsequentLiquidityUsesOptimalRatioBothBranches() public {
        _seedV2();
        (uint256 x, uint256 y, uint256 shares) = v2.addLiquidity(10 ether, 30 ether, 0, 0, 0, D);
        assertEq(x, 10 ether);
        assertEq(y, 10 ether);
        assertEq(shares, 10 ether);
        (x, y, shares) = v2.addLiquidity(30 ether, 10 ether, 0, 0, 0, D);
        assertEq(x, 10 ether);
        assertEq(y, 10 ether);
        assertEq(shares, 10 ether);
        _assertV2Reserves();
    }

    function test_TransferLpAndRemoveLiquidity() public {
        _seedV2();
        v2.transfer(ALICE, 10 ether);
        vm.prank(ALICE);
        (uint256 x, uint256 y) = v2.removeLiquidity(10 ether, 10 ether, 10 ether, ALICE, D);
        assertEq(x, 10 ether);
        assertEq(y, 10 ether);
        assertEq(a.balanceOf(ALICE), x);
        assertEq(b.balanceOf(ALICE), y);
        assertEq(v2.balanceOf(ALICE), 0);
        _assertV2Reserves();
    }

    function test_RemoveAllUserSharesKeepsMinimumLocked() public {
        _seedV2();
        v2.removeLiquidity(R - 1000, 0, 0, address(this), D);
        assertEq(v2.totalSupply(), 1000);
        assertEq(a.balanceOf(address(v2)), 1000);
        assertEq(b.balanceOf(address(v2)), 1000);
        _assertV2Reserves();
    }

    function test_BothDirectionsAndAmountInEvents() public {
        _seedV2();
        uint256 out = 10 ether * 997 * R / (R * 1000 + 10 ether * 997);
        a.transfer(address(v2), 10 ether);
        vm.expectEmit(true, true, false, true, address(v2));
        emit Swap(address(this), 10 ether, 0, 0, out, BOB);
        v2.swap(0, out, BOB, "");
        assertEq(b.balanceOf(BOB), out);
        (uint112 r0, uint112 r1) = v2.getReserves();
        uint256 reverse = 5 ether * 997 * uint256(r0) / (uint256(r1) * 1000 + 5 ether * 997);
        b.transfer(address(v2), 5 ether);
        vm.expectEmit(true, true, false, true, address(v2));
        emit Swap(address(this), 0, 5 ether, reverse, 0, BOB);
        v2.swap(reverse, 0, BOB, "");
        assertEq(a.balanceOf(BOB), reverse);
        _assertV2Reserves();
    }

    function test_NoFeeQuoteFailsKAndAtomicPrepaymentRollsBack() public {
        _seedV2();
        AtomicSwap caller = new AtomicSwap();
        a.approve(address(caller), D);
        uint256 userBefore = a.balanceOf(address(this));
        uint256 tooMuch = 10 ether * R / (R + 10 ether);
        vm.expectRevert(MiniUniswapV2.InvariantK.selector);
        caller.payAndSwap(v2, a, 10 ether, 0, tooMuch);
        assertEq(a.balanceOf(address(this)), userBefore);
        assertEq(a.balanceOf(address(v2)), R);
        assertEq(b.balanceOf(address(v2)), R);
        _assertV2Reserves();
    }

    function test_OneWeiMoreThan997QuoteFails() public {
        _seedV2();
        AtomicSwap caller = new AtomicSwap();
        a.approve(address(caller), D);
        uint256 out = PoolMath.getAmountOut(1 ether, R, R);
        vm.expectRevert(MiniUniswapV2.InvariantK.selector);
        caller.payAndSwap(v2, a, 1 ether, 0, out + 1);
        _assertV2Reserves();
    }

    function test_TradingFeesAccrueToLpAndIncreaseK() public {
        _seedV2();
        router.swapV2(v2, true, 10 ether, 0, BOB, D);
        (uint112 r0, uint112 r1) = v2.getReserves();
        assertGt(uint256(r0) * r1, R * R);
        assertEq(uint256(r0), R + 10 ether); // all input, including 0.3%, stays in pool
        assertGe((uint256(r0) * 1000 - 10 ether * 3) * uint256(r1) * 1000, R * R * 1_000_000);
        uint256 shares = 10 ether;
        (uint256 x, uint256 y) = v2.removeLiquidity(shares, 0, 0, BOB, D);
        assertEq(x, shares * r0 / R);
        assertEq(y, shares * r1 / R);
        _assertV2Reserves();
    }

    function test_RouterSlippageAndDeadlineAreAtomic() public {
        _seedV2();
        uint256 beforeTokens = a.balanceOf(address(this));
        vm.expectRevert(MiniRouter.Slippage.selector);
        router.swapV2(v2, true, 10 ether, 10 ether, BOB, D);
        vm.warp(100);
        vm.expectRevert(MiniRouter.Expired.selector);
        router.swapV2(v2, true, 1 ether, 0, BOB, 99);
        assertEq(a.balanceOf(address(this)), beforeTokens);
        _assertV2Reserves();
    }

    function test_LiquiditySlippageChecksAllMinima() public {
        _seedV2();
        vm.expectRevert(PoolShares.Slippage.selector);
        v2.addLiquidity(10 ether, 30 ether, 0, 11 ether, 0, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v2.addLiquidity(30 ether, 10 ether, 11 ether, 0, 0, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v2.addLiquidity(10 ether, 10 ether, 0, 0, 10 ether + 1, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v2.removeLiquidity(10 ether, 10 ether + 1, 0, BOB, D);
        vm.expectRevert(PoolShares.Slippage.selector);
        v2.removeLiquidity(10 ether, 0, 10 ether + 1, BOB, D);
        assertEq(v2.balanceOf(address(this)), R - 1000);
    }

    function test_LiquidityDeadlinesAndBoundary() public {
        _seedV2();
        vm.warp(100);
        vm.expectRevert(PoolShares.Expired.selector);
        v2.addLiquidity(1 ether, 1 ether, 0, 0, 0, 99);
        vm.expectRevert(PoolShares.Expired.selector);
        v2.removeLiquidity(1 ether, 0, 0, BOB, 99);
        v2.addLiquidity(1 ether, 1 ether, 0, 0, 0, 100);
    }

    function test_EmptyPoolZeroInputsAndMinimumLiquidity() public {
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        v2.swap(0, 1, BOB, "");
        vm.expectRevert(PoolShares.ZeroLiquidity.selector);
        v2.removeLiquidity(1, 0, 0, BOB, D);
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        v2.addLiquidity(0, 1 ether, 0, 0, 0, D);
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        v2.addLiquidity(1 ether, 0, 0, 0, 0, D);
        vm.expectRevert(PoolShares.ZeroLiquidity.selector);
        v2.addLiquidity(1000, 1000, 0, 0, 0, D);
        _seedV2();
        vm.expectRevert(MiniUniswapV2.InsufficientOutput.selector);
        v2.swap(0, 0, BOB, "");
        vm.expectRevert(PoolMath.InvalidAmount.selector);
        router.swapV2(v2, true, 0, 0, BOB, D);
        vm.expectRevert(PoolShares.ZeroLiquidity.selector);
        v2.removeLiquidity(0, 0, 0, BOB, D);
    }

    function test_InsufficientOutputReservesAndMissingInput() public {
        _seedV2();
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        v2.swap(R, 0, BOB, "");
        vm.expectRevert(PoolMath.InsufficientLiquidity.selector);
        v2.swap(0, R, BOB, "");
        vm.expectRevert(MiniUniswapV2.InsufficientInput.selector);
        v2.swap(0, 1 ether, BOB, "");
        assertEq(b.balanceOf(BOB), 0);
        _assertV2Reserves();
    }

    function test_MissingBalanceAllowanceAndLp() public {
        _seedV2();
        a.approve(address(router), 0);
        vm.expectRevert();
        router.swapV2(v2, true, 1 ether, 0, BOB, D);
        vm.startPrank(ALICE);
        a.approve(address(router), D);
        vm.expectRevert();
        router.swapV2(v2, true, 1 ether, 0, BOB, D);
        vm.expectRevert();
        v2.removeLiquidity(1 ether, 0, 0, BOB, D);
        vm.stopPrank();
        _assertV2Reserves();
    }

    function test_FailedSecondTokenDepositRollsBackFirst() public {
        uint256 beforeA = a.balanceOf(address(this));
        b.setFailTransfers(true);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(b)));
        v2.addLiquidity(R, R, 0, 0, 0, D);
        assertEq(a.balanceOf(address(this)), beforeA);
        assertEq(a.balanceOf(address(v2)), 0);
        assertEq(v2.totalSupply(), 0);
    }

    function test_FailedOutputTransferRollsBackPrepaymentAndBurn() public {
        _seedV2();
        b.setFailTransfers(true);
        uint256 beforeA = a.balanceOf(address(this));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(b)));
        router.swapV2(v2, true, 1 ether, 0, BOB, D);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(b)));
        v2.removeLiquidity(1 ether, 0, 0, BOB, D);
        assertEq(a.balanceOf(address(this)), beforeA);
        assertEq(a.balanceOf(BOB), 0);
        assertEq(v2.balanceOf(address(this)), R - 1000);
        _assertV2Reserves();
    }

    function test_NoReturnTokenIsSupported() public {
        NoReturnToken token = new NoReturnToken();
        MiniUniswapV2 pair = new MiniUniswapV2(address(a), address(token));
        token.mint(address(this), R);
        token.approve(address(pair), R);
        a.approve(address(pair), D);
        pair.addLiquidity(R, R, 0, 0, 0, D);
        router.swapV2(pair, true, 1 ether, 0, BOB, D);
        pair.removeLiquidity(1 ether, 0, 0, BOB, D);
        assertGt(token.balanceOf(BOB), 0);
    }

    function test_TaxedInputDepositRejectedAndSwapFailsK() public {
        a.setTaxTransfers(true);
        vm.expectRevert(PoolShares.UnsupportedToken.selector);
        v2.addLiquidity(R, R, 0, 0, 0, D);
        a.setTaxTransfers(false);
        _seedV2();
        a.setTaxTransfers(true);
        vm.expectRevert(MiniUniswapV2.InvariantK.selector);
        router.swapV2(v2, true, 1 ether, 0, BOB, D);
        _assertV2Reserves();
    }

    function test_TokenHookCannotReenterDepositSwapOrWithdrawal() public {
        a.setHook(address(v2), abi.encodeCall(v2.sync, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        v2.addLiquidity(R, R, 0, 0, 0, D);
        a.setHook(address(0), "");
        _seedV2();
        b.setHook(address(v2), abi.encodeCall(v2.sync, ()));
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        router.swapV2(v2, true, 1 ether, 0, BOB, D);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        v2.removeLiquidity(1 ether, 0, 0, BOB, D);
        _assertV2Reserves();
    }

    function test_DonationSyncAndLiquidityDoNotMintDonatedValue() public {
        _seedV2();
        a.transfer(address(v2), 100 ether);
        b.transfer(address(v2), 100 ether);
        // Deposits use current balances, so donated tokens accrue to existing LPs.
        (,, uint256 shares) = v2.addLiquidity(10 ether, 10 ether, 0, 0, 0, D);
        assertEq(shares, 5 ether);
        a.transfer(address(v2), 1 ether);
        v2.sync();
        _assertV2Reserves();
        vm.expectRevert(MiniUniswapV2.InsufficientInput.selector);
        v2.swap(0, 1, BOB, ""); // synced donation is no longer swap input
    }

    function test_UnsyncedTransferIsPublicInputNotAnEscrow() public {
        _seedV2();
        a.transfer(address(v2), 1 ether);
        uint256 out = PoolMath.getAmountOut(1 ether, R, R);
        vm.prank(ALICE); // demonstrates why users must use the atomic router
        v2.swap(0, out, ALICE, "");
        assertEq(b.balanceOf(ALICE), out);
        _assertV2Reserves();
    }

    function test_ReserveOverflowAndInvalidTokens() public {
        vm.expectRevert(PoolShares.InvalidToken.selector);
        new MiniUniswapV2(address(a), address(a));
        vm.expectRevert(PoolShares.InvalidToken.selector);
        new MiniUniswapV2(address(a), ALICE);
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        v2.addLiquidity(uint256(type(uint112).max) + 1, R, 0, 0, 0, D);
        _seedV2();
        a.mint(address(v2), uint256(type(uint112).max));
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        v2.sync();
        vm.expectRevert(PoolMath.ReserveOverflow.selector);
        v2.swap(0, 1, BOB, "");
        assertEq(b.balanceOf(BOB), 0);
    }

    function test_InvalidRecipientsAndMissingCallbackContract() public {
        _seedV2();
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v2.swap(0, 1, address(0), "");
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v2.swap(0, 1, address(v2), "");
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v2.swap(0, 1, address(a), "");
        vm.expectRevert(PoolShares.InvalidRecipient.selector);
        v2.swap(0, 1, address(b), "");
        vm.expectRevert();
        v2.swap(0, 1 ether, BOB, hex"01");
        _assertV2Reserves();
    }

    function testFuzz_SwapsPreserveFeeAdjustedK(uint96 raw, bool direction) public {
        _seedV2();
        uint256 input = bound(uint256(raw), 1000, 50 ether);
        uint256 expected = input * 997 * R / (R * 1000 + input * 997);
        assertEq(router.swapV2(v2, direction, input, expected, BOB, D), expected);
        (uint112 r0, uint112 r1) = v2.getReserves();
        uint256 adjusted0 = uint256(r0) * 1000 - (direction ? input * 3 : 0);
        uint256 adjusted1 = uint256(r1) * 1000 - (direction ? 0 : input * 3);
        assertGe(adjusted0 * adjusted1, R * R * 1_000_000);
        assertGe(uint256(r0) * r1, R * R);
        _assertV2Reserves();
    }

    function testFuzz_LpRoundTripCannotCreateValue(uint96 raw) public {
        _seedV2();
        uint256 amount = bound(uint256(raw), 1000, 50 ether);
        a.mint(ALICE, amount);
        b.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v2), D);
        b.approve(address(v2), D);
        (,, uint256 shares) = v2.addLiquidity(amount, amount, 0, 0, 0, D);
        (uint256 x, uint256 y) = v2.removeLiquidity(shares, 0, 0, ALICE, D);
        vm.stopPrank();
        assertLe(x, amount);
        assertLe(y, amount);
        _assertV2Reserves();
    }

    function testFuzz_MixedSequenceKeepsReservesAndSwapK(uint256 seed) public {
        _seedV2();
        for (uint256 i; i < 24; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 amount = 1e12 + seed % 1 ether;
            if (seed % 3 == 0) {
                v2.addLiquidity(amount, amount, 0, 0, 0, D);
            } else if (seed % 3 == 1) {
                v2.removeLiquidity(amount, 0, 0, address(this), D);
            } else {
                (uint112 before0, uint112 before1) = v2.getReserves();
                router.swapV2(v2, seed % 2 == 0, amount, 0, BOB, D);
                (uint112 after0, uint112 after1) = v2.getReserves();
                assertGe(uint256(after0) * after1, uint256(before0) * before1);
            }
            _assertV2Reserves();
            assertEq(v2.balanceOf(address(v2)), 1000);
        }
    }
}
