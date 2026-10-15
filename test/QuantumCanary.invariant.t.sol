// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuantumCanary} from "../src/QuantumCanary.sol";

/// @dev A closed set of holders and an independent balance/allowance model.
contract CanaryHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    QuantumCanary public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = makeAddr("holder one");
        actors[1] = makeAddr("holder two");
        actors[2] = makeAddr("holder three");
        actors[3] = makeAddr("holder four");
        token = new QuantumCanary();
        require(token.transfer(actors[0], SUPPLY));
        expectedBalance[actors[0]] = SUPPLY;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);

        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function setApproval(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = unlimited ? type(uint256).max : bound(amount, 0, SUPPLY);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, available < approved ? available : approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }
}

contract QuantumCanaryInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    CanaryHandler internal handler;
    QuantumCanary internal token;

    function setUp() public {
        handler = new CanaryHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = CanaryHandler.move.selector;
        selectors[1] = CanaryHandler.setApproval.selector;
        selectors[2] = CanaryHandler.spend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndBalancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 actual = token.balanceOf(actor);
            assertEq(actual, handler.expectedBalance(actor));
            sum += actual;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_AllowancesMatchModel() public view {
        for (uint256 i; i < 4; ++i) {
            for (uint256 j; j < 4; ++j) {
                address owner = handler.actors(i);
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
