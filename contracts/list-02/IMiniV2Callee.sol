// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

interface IMiniV2Callee {
    /// @notice Callback flash swapu; odbiorca weryfikuje parę i inicjatora.
    function miniUniswapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external;
}
