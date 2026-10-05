// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

/// @notice A small counter for learning Solidity and testing with Hardhat.
contract Counter {
    uint256 public value;

    event Increment(uint256 amount);
    error ZeroIncrement();

    function inc() public {
        incBy(1);
    }

    function incBy(uint256 amount) public {
        if (amount == 0) revert ZeroIncrement();
        value += amount;
        emit Increment(amount);
    }
}
