// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PoolShares} from "./PoolShares.sol";
import {PoolMath} from "./PoolMath.sol";
import {IMiniV2Callee} from "./IMiniV2Callee.sol";

/// @notice Para ERC20/ERC20; kolejność tokenów ustala konstruktor.
contract MiniUniswapV2 is PoolShares {
    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;

    error InsufficientOutput();
    error InsufficientInput();
    error InvariantK();

    event Sync(uint112 reserve0, uint112 reserve1);

    event LiquidityAdded(
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    );

    event LiquidityRemoved(
        address indexed provider,
        address indexed to,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    );

    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    constructor(
        address token0_,
        address token1_
    ) PoolShares("Mini V2 LP", "MV2-LP") {
        _validateToken(token0_);
        _validateToken(token1_);

        if (token0_ == token1_) {
            revert InvalidToken();
        }

        token0 = IERC20(token0_);
        token1 = IERC20(token1_);
    }

    function getReserves() external view returns (uint112, uint112) {
        return (reserve0, reserve1);
    }

    /// @notice Pobiera tokeny w proporcji puli i emituje udziały LP.
    function addLiquidity(
        uint256 desired0,
        uint256 desired1,
        uint256 min0,
        uint256 min1,
        uint256 minShares,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amount0, uint256 amount1, uint256 shares)
    {
        if (desired0 == 0 || desired1 == 0) {
            revert PoolMath.InvalidAmount();
        }

        PoolMath.checkBalances(desired0, desired1);
        (uint256 balance0, uint256 balance1) = _balances();
        PoolMath.checkBalances(balance0, balance1);
        bool initial = totalSupply() == 0;

        if (initial) {
            (amount0, amount1) = (desired0, desired1);
        } else {
            if (balance0 == 0 || balance1 == 0) {
                revert ZeroLiquidity();
            }

            // Dobieramy wpłaty do proporcji sald, bez pobierania zbędnej nadwyżki.
            uint256 optimal1 = desired0 * balance1 / balance0;

            if (optimal1 <= desired1) {
                (amount0, amount1) = (desired0, optimal1);
            } else {
                (amount0, amount1) = (desired1 * balance0 / balance1, desired1);
            }
        }

        PoolMath.checkBalances(balance0 + amount0, balance1 + amount1);

        if (amount0 == 0 || amount1 == 0) {
            revert ZeroLiquidity();
        }

        if (amount0 < min0 || amount1 < min1) {
            revert Slippage();
        }

        if (initial) {
            uint256 root = Math.sqrt(amount0 * amount1);

            if (root <= MINIMUM_LIQUIDITY) {
                revert ZeroLiquidity();
            }

            shares = root - MINIMUM_LIQUIDITY;
        } else {
            // O liczbie LP decyduje mniejszy udział wynikający z obu wpłat.
            shares = Math.min(
                amount0 * totalSupply() / balance0,
                amount1 * totalSupply() / balance1
            );
        }

        if (shares == 0) {
            revert ZeroLiquidity();
        }

        if (shares < minShares) {
            revert Slippage();
        }

        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);

        (uint256 next0, uint256 next1) = _balances();

        // Odrzucamy tokeny, które nie dostarczyły zadeklarowanych kwot.
        if (next0 != balance0 + amount0 || next1 != balance1 + amount1) {
            revert UnsupportedToken();
        }

        _issueShares(msg.sender, shares, minShares, initial);
        _update(next0, next1);

        emit LiquidityAdded(msg.sender, amount0, amount1, shares);
    }

    /// @notice Spala udziały wywołującego i wypłaca jego część obu sald.
    function removeLiquidity(
        uint256 shares,
        uint256 min0,
        uint256 min1,
        address to,
        uint256 deadline
    )
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        _validateRecipient(to);

        if (shares == 0 || totalSupply() == 0) {
            revert ZeroLiquidity();
        }

        (uint256 balance0, uint256 balance1) = _balances();
        amount0 = Math.mulDiv(shares, balance0, totalSupply());
        amount1 = Math.mulDiv(shares, balance1, totalSupply());

        if (amount0 == 0 || amount1 == 0) {
            revert ZeroLiquidity();
        }

        if (amount0 < min0 || amount1 < min1) {
            revert Slippage();
        }

        // Udziały znikają przed zewnętrznymi transferami.
        _burn(msg.sender, shares);

        token0.safeTransfer(to, amount0);
        token1.safeTransfer(to, amount1);

        (balance0, balance1) = _balances();
        _update(balance0, balance1);

        emit LiquidityRemoved(msg.sender, to, amount0, amount1, shares);
    }

    /// @notice Wypłaca dokładne kwoty; spłata musi nastąpić w tej samej transakcji.
    /// @dev Dla zwykłych swapów minOut i deadline sprawdza MiniRouter.
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) {
            revert InsufficientOutput();
        }

        (uint256 old0, uint256 old1) = (reserve0, reserve1);

        if (amount0Out >= old0 || amount1Out >= old1) {
            revert PoolMath.InsufficientLiquidity();
        }

        _validateRecipient(to);

        // Optymistyczna wypłata poprzedza callback i końcową kontrolę spłaty.
        if (amount0Out != 0) {
            token0.safeTransfer(to, amount0Out);
        }

        if (amount1Out != 0) {
            token1.safeTransfer(to, amount1Out);
        }

        if (data.length != 0) {
            IMiniV2Callee(to).miniUniswapV2Call(
                msg.sender,
                amount0Out,
                amount1Out,
                data
            );
        }

        (uint256 balance0, uint256 balance1) = _balances();

        // Limit przed mnożeniem: uint112² × 1000² mieści się w uint256.
        PoolMath.checkBalances(balance0, balance1);

        // Wejście to nadwyżka ponad rezerwy pozostałe po wypłacie.
        uint256 amount0In = balance0 > old0 - amount0Out
            ? balance0 - (old0 - amount0Out)
            : 0;

        uint256 amount1In = balance1 > old1 - amount1Out
            ? balance1 - (old1 - amount1Out)
            : 0;

        if (amount0In == 0 && amount1In == 0) {
            revert InsufficientInput();
        }

        {
            // Odejmujemy 0,3% tylko od wejścia; fizycznie cała wpłata zostaje w puli.
            uint256 adjusted0 = balance0 * 1000 - amount0In * 3;
            uint256 adjusted1 = balance1 * 1000 - amount1In * 3;

            if (adjusted0 * adjusted1 < old0 * old1 * 1_000_000) {
                revert InvariantK();
            }
        }

        // Nowe rezerwy zatwierdzamy dopiero po spełnieniu warunku k.
        _update(balance0, balance1);

        emit Swap(
            msg.sender,
            amount0In,
            amount1In,
            amount0Out,
            amount1Out,
            to
        );
    }

    /// @notice Włącza darowizny do rezerw; sam transfer nie rezerwuje prawa do swapu.
    function sync() external nonReentrant {
        (uint256 balance0, uint256 balance1) = _balances();
        _update(balance0, balance1);
    }

    function _balances() private view returns (uint256, uint256) {
        return (token0.balanceOf(address(this)), token1.balanceOf(address(this)));
    }

    function _update(uint256 balance0, uint256 balance1) private {
        PoolMath.checkBalances(balance0, balance1);

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);

        emit Sync(reserve0, reserve1);
    }

    function _validateRecipient(address to) internal view override {
        super._validateRecipient(to);

        if (to == address(token0) || to == address(token1)) {
            revert InvalidRecipient();
        }
    }
}
