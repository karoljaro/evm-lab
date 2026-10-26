// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolShares} from "./PoolShares.sol";
import {PoolMath} from "./PoolMath.sol";

/// @notice Pula ERC20/ETH dla zwykłego tokena bez rebasingu i podatku od transferu.
contract MiniUniswapV1 is PoolShares {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    // Snapshot rezerw z ostatniej zakończonej operacji.
    uint112 private reserveToken;
    uint112 private reserveEth;

    error EthTransferFailed();

    event Sync(uint112 tokenReserve, uint112 ethReserve);

    event LiquidityAdded(
        address indexed provider,
        uint256 tokens,
        uint256 eth,
        uint256 shares
    );

    event LiquidityRemoved(
        address indexed provider,
        address indexed to,
        uint256 tokens,
        uint256 eth,
        uint256 shares
    );

    event Swap(
        address indexed sender,
        address indexed to,
        bool ethToToken,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address token_) PoolShares("Mini V1 LP", "MV1-LP") {
        _validateToken(token_);

        token = IERC20(token_);
    }

    function getReserves() external view returns (uint112, uint112) {
        return (reserveToken, reserveEth);
    }

    /// @notice Dodaje płynność i przyznaje dostawcy udziały LP.
    /// @dev Zużywa całe przesłane ETH, pobiera tylko potrzebne tokeny.
    function addLiquidity(
        uint256 maxTokens,
        uint256 minShares,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        ensure(deadline)
        returns (uint256 tokens, uint256 shares)
    {
        if (msg.value == 0 || maxTokens == 0) {
            revert PoolMath.InvalidAmount();
        }

        uint256 tokenBefore = token.balanceOf(address(this));

        // msg.value jest już w saldzie kontraktu, ale nie należy do starych rezerw.
        uint256 ethBefore = address(this).balance - msg.value;
        bool initial = totalSupply() == 0;

        if (initial) {
            tokens = maxTokens;
            PoolMath.checkBalances(tokenBefore + tokens, ethBefore + msg.value);

            // Pierwsza emisja LP wynika ze średniej geometrycznej obu wpłat.
            uint256 root = Math.sqrt(tokens * msg.value);

            if (root <= MINIMUM_LIQUIDITY) {
                revert ZeroLiquidity();
            }

            shares = root - MINIMUM_LIQUIDITY;
        } else {
            PoolMath.checkBalances(tokenBefore, ethBefore + msg.value);

            if (tokenBefore == 0 || ethBefore == 0) {
                revert ZeroLiquidity();
            }

            // Zachowujemy proporcję rezerw; wymaganą wpłatę tokenów zaokrąglamy w górę.
            tokens = Math.mulDiv(
                msg.value,
                tokenBefore,
                ethBefore,
                Math.Rounding.Ceil
            );

            if (tokens > maxTokens) {
                revert Slippage();
            }

            PoolMath.checkBalances(tokenBefore + tokens, ethBefore + msg.value);
            shares = Math.mulDiv(msg.value, totalSupply(), ethBefore);
        }
        if (shares < minShares) {
            revert Slippage();
        }

        if (shares == 0) {
            revert ZeroLiquidity();
        }

        token.safeTransferFrom(msg.sender, address(this), tokens);

        if (token.balanceOf(address(this)) != tokenBefore + tokens) {
            revert UnsupportedToken();
        }

        _issueShares(msg.sender, shares, minShares, initial);
        _update();

        emit LiquidityAdded(msg.sender, tokens, msg.value, shares);
    }

    /// @notice Spala LP i wypłaca proporcjonalną część obu aktywów.
    function removeLiquidity(
        uint256 shares,
        uint256 minTokens,
        uint256 minEth,
        address payable to,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 tokens, uint256 eth)
    {
        _validateRecipient(to);

        if (shares == 0) {
            revert ZeroLiquidity();
        }

        uint256 supply = totalSupply();

        if (supply == 0) {
            revert ZeroLiquidity();
        }

        tokens = Math.mulDiv(shares, token.balanceOf(address(this)), supply);
        eth = Math.mulDiv(shares, address(this).balance, supply);

        if (tokens == 0 || eth == 0) {
            revert ZeroLiquidity();
        }

        if (tokens < minTokens || eth < minEth) {
            revert Slippage();
        }

        // LP spalamy przed transferami; revert przywraca też udziały.
        _burn(msg.sender, shares);

        token.safeTransfer(to, tokens);
        _sendEth(to, eth);
        _update();

        emit LiquidityRemoved(msg.sender, to, tokens, eth, shares);
    }

    /// @notice Zamienia przesłane ETH na co najmniej minOut tokenów.
    function ethToTokenSwap(
        uint256 minOut,
        address to,
        uint256 deadline
    )
        external
        payable
        nonReentrant
        ensure(deadline)
        returns (uint256 amountOut)
    {
        _validateRecipient(to);

        uint256 ethBefore = address(this).balance - msg.value;
        uint256 tokenBefore = token.balanceOf(address(this));
        PoolMath.checkBalances(tokenBefore, ethBefore + msg.value);
        amountOut = PoolMath.getAmountOut(msg.value, ethBefore, tokenBefore);

        if (amountOut == 0 || amountOut < minOut) {
            revert Slippage();
        }

        token.safeTransfer(to, amountOut);
        _update();

        emit Swap(msg.sender, to, true, msg.value, amountOut);
    }

    /// @notice Pobiera tokeny przez allowance i wypłaca co najmniej minOut ETH.
    function tokenToEthSwap(
        uint256 amountIn,
        uint256 minOut,
        address payable to,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amountOut)
    {
        _validateRecipient(to);

        uint256 tokenBefore = token.balanceOf(address(this));
        uint256 ethBefore = address(this).balance;
        PoolMath.checkBalances(tokenBefore + amountIn, ethBefore);
        amountOut = PoolMath.getAmountOut(amountIn, tokenBefore, ethBefore);

        if (amountOut == 0 || amountOut < minOut) {
            revert Slippage();
        }

        token.safeTransferFrom(msg.sender, address(this), amountIn);

        // ETH wypłacamy dopiero po potwierdzeniu pełnej wpłaty tokenów.
        if (token.balanceOf(address(this)) != tokenBefore + amountIn) {
            revert UnsupportedToken();
        }

        _sendEth(to, amountOut);
        _update();

        emit Swap(msg.sender, to, false, amountIn, amountOut);
    }

    /// @notice Włącza darowizny tokenów i wymuszone wpłaty ETH do zapisanych rezerw.
    function sync() external nonReentrant {
        _update();
    }

    function _update() private {
        // Zapisujemy rzeczywiste salda po zakończeniu transferów.
        uint256 tokens = token.balanceOf(address(this));
        uint256 eth = address(this).balance;

        PoolMath.checkBalances(tokens, eth);

        reserveToken = uint112(tokens);
        reserveEth = uint112(eth);

        emit Sync(reserveToken, reserveEth);
    }

    function _sendEth(address payable to, uint256 amount) private {
        (bool success,) = to.call{value: amount}("");

        // Odrzucenie ETH przez odbiorcę cofa całą operację.
        if (!success) {
            revert EthTransferFailed();
        }
    }

    function _validateRecipient(address to) internal view override {
        super._validateRecipient(to);

        if (to == address(token)) {
            revert InvalidRecipient();
        }
    }
}
