// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Wspólne tokeny LP, limity użytkownika i blokada ponownego wejścia.
abstract contract PoolShares is ERC20, ReentrancyGuard {
    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    error Expired();
    error InvalidToken();
    error InvalidRecipient();
    error Slippage();
    error ZeroLiquidity();
    error UnsupportedToken();

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    modifier ensure(uint256 deadline) {
        // Transakcja jest ważna także dokładnie w chwili deadline.
        if (block.timestamp > deadline) {
            revert Expired();
        }

        _;
    }

    function _validateToken(address token) internal view {
        if (token.code.length == 0 || token == address(this)) {
            revert InvalidToken();
        }
    }

    function _validateRecipient(address to) internal view virtual {
        if (to == address(0) || to == address(this)) {
            revert InvalidRecipient();
        }
    }

    function _issueShares(
        address to,
        uint256 shares,
        uint256 minimum,
        bool initial
    ) internal {
        if (shares == 0) {
            revert ZeroLiquidity();
        }

        if (shares < minimum) {
            revert Slippage();
        }

        // Pierwsze LP na adresie puli pozostają trwale zablokowane.
        if (initial) {
            _mint(address(this), MINIMUM_LIQUIDITY);
        }

        _mint(to, shares);
    }
}
