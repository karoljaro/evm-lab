// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

/// @notice Wspólne wzory cenowe i kontrola zakresu rezerw.
library PoolMath {
    uint256 internal constant MAX_RESERVE = type(uint112).max;

    error InvalidAmount();
    error InsufficientLiquidity();
    error ReserveOverflow();

    function checkBalances(
        uint256 balance0,
        uint256 balance1
    ) internal pure {
        if (balance0 > MAX_RESERVE || balance1 > MAX_RESERVE) {
            revert ReserveOverflow();
        }
    }

    /// @notice Oblicza wyjście dla zadanej wpłaty, zaokrąglając wynik w dół.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountIn == 0) {
            revert InvalidAmount();
        }

        checkBalances(amountIn, 0);
        checkBalances(reserveIn, reserveOut);

        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }

        // W cenie uwzględniamy 99,7% wejścia; pozostałe 0,3% to opłata dla LP.
        uint256 inputWithFee = amountIn * 997;

        return inputWithFee * reserveOut / (reserveIn * 1000 + inputWithFee);
    }

    /// @notice Oblicza wpłatę potrzebną do uzyskania zadanej kwoty wyjścia.
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountOut == 0) {
            revert InvalidAmount();
        }

        checkBalances(reserveIn, reserveOut);

        if (reserveIn == 0 || amountOut >= reserveOut) {
            revert InsufficientLiquidity();
        }

        // Zapas 1 wei jak w V2, także przy dzieleniu bez reszty.
        return reserveIn * amountOut * 1000 / ((reserveOut - amountOut) * 997) + 1;
    }
}
