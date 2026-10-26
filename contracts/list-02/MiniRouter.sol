// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MiniUniswapV1} from "./MiniUniswapV1.sol";
import {MiniUniswapV2} from "./MiniUniswapV2.sol";
import {PoolMath} from "./PoolMath.sol";

/// @notice Atomowe wymiany przez dwie pule V1 albo jedną parę V2.
contract MiniRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error Expired();
    error Slippage();
    error InvalidRoute();
    error UnsupportedToken();

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert Expired();
        }

        _;
    }

    // Odbiera ETH z pierwszego etapu wymiany V1.
    receive() external payable {}

    /// @notice Wykonuje trasę token A → ETH → token B w jednej transakcji.
    function swapV1ToV1(
        MiniUniswapV1 source,
        MiniUniswapV1 destination,
        uint256 amountIn,
        uint256 minEth,
        uint256 minOut,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amountOut)
    {
        if (
            address(source) == address(destination)
                || address(source.token()) == address(destination.token())
        ) {
            revert InvalidRoute();
        }

        IERC20 input = source.token();
        uint256 beforeBalance = input.balanceOf(address(this));

        input.safeTransferFrom(msg.sender, address(this), amountIn);

        if (input.balanceOf(address(this)) != beforeBalance + amountIn) {
            revert UnsupportedToken();
        }

        // Pierwsza pula pobiera tokeny od routera, a otrzymane ETH zasila drugą.
        input.forceApprove(address(source), amountIn);

        uint256 eth = source.tokenToEthSwap(
            amountIn,
            minEth,
            payable(address(this)),
            deadline
        );

        amountOut = destination.ethToTokenSwap{value: eth}(minOut, to, deadline);
    }

    /// @notice Pobiera wejście i wykonuje swap z kontrolą minOut oraz deadline.
    /// @param zeroForOne true oznacza token0 → token1, false odwrotny kierunek.
    function swapV2(
        MiniUniswapV2 pair,
        bool zeroForOne,
        uint256 amountIn,
        uint256 minOut,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amountOut)
    {
        (uint112 reserve0, uint112 reserve1) = pair.getReserves();

        amountOut = zeroForOne
            ? PoolMath.getAmountOut(amountIn, reserve0, reserve1)
            : PoolMath.getAmountOut(amountIn, reserve1, reserve0);
        if (amountOut == 0 || amountOut < minOut) {
            revert Slippage();
        }

        IERC20 input = zeroForOne ? pair.token0() : pair.token1();

        // Transfer i swap są atomowe; błąd pary cofa również pobranie tokenów.
        input.safeTransferFrom(msg.sender, address(pair), amountIn);

        pair.swap(
            zeroForOne ? 0 : amountOut,
            zeroForOne ? amountOut : 0,
            to,
            ""
        );
    }
}
