// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {PoolShares} from "../../../contracts/list-02/PoolShares.sol";
import {PoolMath} from "../../../contracts/list-02/PoolMath.sol";
import {MiniUniswapV1} from "../../../contracts/list-02/MiniUniswapV1.sol";
import {MiniUniswapV2} from "../../../contracts/list-02/MiniUniswapV2.sol";
import {MiniRouter} from "../../../contracts/list-02/MiniRouter.sol";
import {LabToken, NoReturnToken} from "../../../contracts/list-02/mocks/TestTokens.sol";

abstract contract PoolFixture is Test {
    LabToken internal a;
    LabToken internal b;
    MiniUniswapV1 internal v1a;
    MiniUniswapV1 internal v1b;
    MiniUniswapV2 internal v2;
    MiniRouter internal router;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    uint256 internal constant D = type(uint256).max;
    uint256 internal constant R = 100 ether;

    function setUp() public virtual {
        vm.deal(address(this), 100_000 ether);
        vm.deal(ALICE, 1000 ether);
        a = new LabToken("Token A", "A");
        b = new LabToken("Token B", "B");
        v1a = new MiniUniswapV1(address(a));
        v1b = new MiniUniswapV1(address(b));
        v2 = new MiniUniswapV2(address(a), address(b));
        router = new MiniRouter();
        a.mint(address(this), 1_000_000 ether);
        b.mint(address(this), 1_000_000 ether);
        a.approve(address(v1a), D);
        b.approve(address(v1b), D);
        a.approve(address(v2), D);
        b.approve(address(v2), D);
        a.approve(address(router), D);
        b.approve(address(router), D);
    }

    receive() external payable {}

    function _seedV1() internal { v1a.addLiquidity{value: R}(R, 0, D); }
    function _seedV2() internal { v2.addLiquidity(R, R, 0, 0, 0, D); }

    function _assertV1Reserves() internal view {
        (uint112 rt, uint112 re) = v1a.getReserves();
        assertEq(rt, a.balanceOf(address(v1a)));
        assertEq(re, address(v1a).balance);
    }

    function _assertV2Reserves() internal view {
        (uint112 r0, uint112 r1) = v2.getReserves();
        assertEq(r0, a.balanceOf(address(v2)));
        assertEq(r1, b.balanceOf(address(v2)));
    }
}

contract EthReceiver {
    MiniUniswapV1 public immutable pool;
    bool public reject;
    bool public reenter;
    bool public swallow;
    bool public blocked;

    constructor(MiniUniswapV1 pool_) { pool = pool_; }
    function configure(bool reject_, bool reenter_, bool swallow_) external {
        reject = reject_; reenter = reenter_; swallow = swallow_;
    }
    receive() external payable {
        require(!reject, "reject ETH");
        if (reenter) {
            (bool success, bytes memory reason) = address(pool).call(abi.encodeCall(pool.sync, ()));
            blocked = !success && bytes4(reason) == ReentrancyGuard.ReentrancyGuardReentrantCall.selector;
            if (!swallow && !success) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        }
    }
}

/// @dev Lets tests over-request output while keeping prepayment in the same reverting call.
contract AtomicSwap {
    function payAndSwap(MiniUniswapV2 pair, IERC20 input, uint256 amountIn, uint256 out0, uint256 out1) external {
        input.transferFrom(msg.sender, address(pair), amountIn);
        pair.swap(out0, out1, msg.sender, "");
    }
}
