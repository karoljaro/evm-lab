// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MiniUniswapV2} from "../MiniUniswapV2.sol";
import {IMiniV2Callee} from "../IMiniV2Callee.sol";
import {PoolMath} from "../PoolMath.sol";

/// @notice Arbitraż: pożycz A, sprzedaj za B na drugiej parze, spłać źródło w B.
contract FlashArbitrage is IMiniV2Callee {
    using SafeERC20 for IERC20;

    MiniUniswapV2 public immutable source;
    MiniUniswapV2 public immutable market;
    address public immutable owner;

    bool private active;

    error Unauthorized();
    error InvalidMarket();
    error Expired();
    error NotProfitable();

    constructor(
        MiniUniswapV2 source_,
        MiniUniswapV2 market_
    ) {
        if (
            address(source_) == address(market_)
                || address(source_.token0()) != address(market_.token0())
                || address(source_.token1()) != address(market_.token1())
        ) {
            revert InvalidMarket();
        }

        source = source_;
        market = market_;
        owner = msg.sender;
    }

    function execute(
        uint256 borrow0,
        uint256 minProfit,
        uint256 deadline
    ) external {
        if (msg.sender != owner || active) {
            revert Unauthorized();
        }

        if (block.timestamp > deadline) {
            revert Expired();
        }

        // Flaga wiąże callback z aktualnie rozpoczętą pożyczką.
        active = true;
        source.swap(
            borrow0,
            0,
            address(this),
            abi.encode(minProfit, deadline)
        );

        active = false;
    }

    function miniUniswapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external {
        // Przyjmujemy tylko callback źródłowej pary dotyczący własnej operacji.
        if (
            msg.sender != address(source)
                || sender != address(this)
                || !active
        ) {
            revert Unauthorized();
        }

        if (amount0Out == 0 || amount1Out != 0) {
            revert InvalidMarket();
        }

        (uint256 minProfit, uint256 deadline) = abi.decode(data, (uint256, uint256));

        if (block.timestamp > deadline) {
            revert Expired();
        }

        (uint112 source0, uint112 source1) = source.getReserves();

        // Wyjście w A wyznacza wymaganą spłatę w drugim tokenie, czyli B.
        uint256 repayment = PoolMath.getAmountIn(amount0Out, source1, source0);

        (uint112 market0, uint112 market1) = market.getReserves();
        uint256 proceeds = PoolMath.getAmountOut(amount0Out, market0, market1);

        // Wcześniej wpłacone tokeny nie mogą maskować straty bieżącej wymiany.
        if (proceeds < repayment || proceeds - repayment < minProfit) {
            revert NotProfitable();
        }

        source.token0().safeTransfer(address(market), amount0Out);
        market.swap(0, proceeds, address(this), "");

        IERC20 payment = source.token1();

        // Najpierw spłacamy pulę, a nadwyżkę przekazujemy właścicielowi.
        payment.safeTransfer(address(source), repayment);
        payment.safeTransfer(owner, proceeds - repayment);
    }
}
