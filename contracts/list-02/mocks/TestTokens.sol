// SPDX-License-Identifier: MIT
pragma solidity ^0.8.37;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Publiczne mint/burn i złośliwe zachowania służą wyłącznie testom.
contract LabToken is ERC20 {
    bool public failTransfers;
    bool public taxTransfers;

    address public hookTarget;
    bytes public hookData;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function setFailTransfers(bool value) external {
        failTransfers = value;
    }

    function setTaxTransfers(bool value) external {
        taxTransfers = value;
    }

    function setHook(address target, bytes calldata data) external {
        hookTarget = target;
        hookData = data;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failTransfers) {
            return false;
        }

        _runHook();

        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (failTransfers) {
            return false;
        }

        _runHook();

        if (taxTransfers) {
            // Symulacja tokena pobierającego 1% podatku przy transferFrom.
            _spendAllowance(from, _msgSender(), amount);
            uint256 tax = amount / 100;

            _transfer(from, to, amount - tax);
            _burn(from, tax);

            return true;
        }

        return super.transferFrom(from, to, amount);
    }

    function _runHook() private {
        // Hook pozwala zasymulować próbę ponownego wejścia przez token.
        if (hookTarget != address(0)) {
            (bool success, bytes memory reason) = hookTarget.call(hookData);

            if (!success) {
                assembly ("memory-safe") {
                    revert(add(reason, 32), mload(reason))
                }
            }
        }
    }
}

/// @dev Token bez wartości zwrotnej z transfer/approve, obsługiwany przez SafeERC20.
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function transfer(address to, uint256 amount) external {
        _move(msg.sender, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external {
        require(allowance[from][msg.sender] >= amount, "allowance");

        allowance[from][msg.sender] -= amount;
        _move(from, to, amount);
    }

    function _move(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
