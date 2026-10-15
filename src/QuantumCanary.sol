// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Quantum Canary (CANARY)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative privileges.
contract QuantumCanary is ERC20 {
    /// @notice One billion CANARY, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mint the entire supply once to the immediate deployer (the launch factory on launch).
    constructor() ERC20("Quantum Canary", "CANARY") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
