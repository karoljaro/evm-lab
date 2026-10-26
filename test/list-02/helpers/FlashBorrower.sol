// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {MiniUniswapV2} from "../../../contracts/list-02/MiniUniswapV2.sol";
import {IMiniV2Callee} from "../../../contracts/list-02/IMiniV2Callee.sol";
import {PoolMath} from "../../../contracts/list-02/PoolMath.sol";
import {LabToken} from "../../../contracts/list-02/mocks/TestTokens.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FlashBorrower is IMiniV2Callee {
    enum Mode { Repay, Underpay, NoRepay, Fail, ReenterSwap, ReenterAdd, ReenterRemove, ReenterSync, CatchReentry, OtherToken, Overflow }
    MiniUniswapV2 public immutable pair;
    Mode private mode;
    uint256 public seen0;
    uint256 public seen1;
    bool public blocked;
    error CallbackFailed();

    constructor(MiniUniswapV2 pair_) { pair = pair_; }

    function run(uint256 out0, uint256 out1, Mode mode_) external {
        mode = mode_;
        pair.swap(out0, out1, address(this), hex"01");
    }

    function debt(uint256 amount) public pure returns (uint256) { return (amount * 1000 + 996) / 997; }

    function miniUniswapV2Call(address sender, uint256 out0, uint256 out1, bytes calldata) external {
        require(msg.sender == address(pair) && sender == address(this), "unauthenticated");
        seen0 = pair.token0().balanceOf(address(this));
        seen1 = pair.token1().balanceOf(address(this));
        if (mode == Mode.Fail) revert CallbackFailed();
        if (mode == Mode.NoRepay) return;
        if (mode == Mode.ReenterSwap) pair.swap(0, 1, address(this), "");
        if (mode == Mode.ReenterAdd) pair.addLiquidity(1, 1, 0, 0, 0, type(uint256).max);
        if (mode == Mode.ReenterRemove) pair.removeLiquidity(1, 0, 0, address(this), type(uint256).max);
        if (mode == Mode.ReenterSync) pair.sync();
        if (mode == Mode.CatchReentry) {
            (bool success, bytes memory reason) = address(pair).call(abi.encodeCall(pair.sync, ()));
            blocked = !success && bytes4(reason) == ReentrancyGuard.ReentrancyGuardReentrantCall.selector;
        }
        if (mode == Mode.Overflow) {
            LabToken(address(pair.token0())).mint(address(pair), uint256(type(uint112).max) + 1);
            return;
        }
        if (mode == Mode.OtherToken) {
            (uint112 r0, uint112 r1) = pair.getReserves();
            pair.token1().transfer(address(pair), PoolMath.getAmountIn(out0, r1, r0));
            return;
        }
        if (out0 != 0) pair.token0().transfer(address(pair), debt(out0) - (mode == Mode.Underpay ? 1 : 0));
        if (out1 != 0) pair.token1().transfer(address(pair), debt(out1) - (mode == Mode.Underpay ? 1 : 0));
    }
}
