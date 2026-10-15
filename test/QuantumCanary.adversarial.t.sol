// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {QuantumCanary} from "src/QuantumCanary.sol";

/// @dev Complements the deployment and ERC-20 tests with authorization transitions,
/// uint256 boundaries, failure recovery, and algebraic transfer properties.
/// forge-config: default.fuzz.runs = 1000
contract QuantumCanaryAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    QuantumCanary internal token;
    address internal holder;
    address internal recipient;
    address internal spender;
    address internal otherSpender;

    function setUp() public {
        token = new QuantumCanary();
        holder = makeAddr("adversarial holder");
        recipient = makeAddr("adversarial recipient");
        spender = makeAddr("adversarial spender");
        otherSpender = makeAddr("other adversarial spender");
    }

    function test_OneWeiRoundTrip() public {
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaxMinusOneIsFiniteAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedAllowanceCannotBeReusedAfterBalanceRefill() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, SUPPLY));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);

        vm.prank(holder);
        assertTrue(token.transfer(address(this), SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);

        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCannotSpendEmptyBalanceAndSurvivesRefill() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);

        vm.prank(holder);
        assertTrue(token.transfer(address(this), 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ReplacingInfiniteApprovalWithFiniteAllowanceRestrictsSpender() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), holder, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), holder, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(holder), 1);
    }

    function test_ApprovalCannotBeRedelegatedForAnotherOwnersBalance() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.approve(otherSpender, SUPPLY));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(address(this), recipient, 1);

        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.allowance(address(this), otherSpender), 0);
        assertEq(token.allowance(spender, otherSpender), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(spender), 0);

        // The original spender can still use its own approval after the rejected attempt.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, 1));
        assertEq(token.allowance(address(this), spender), SUPPLY - 1);
        assertEq(token.allowance(spender, otherSpender), SUPPLY);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_TransactionOriginDoesNotAuthorizeTransfers() public {
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, spender, 0, 1));
        vm.prank(spender, holder);
        token.transfer(recipient, 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender, holder);
        token.transferFrom(holder, recipient, 1);

        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromByOwnerRequiresItsOwnApproval() public {
        assertTrue(token.transfer(holder, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, holder, 1);
        assertEq(token.balanceOf(holder), 1);

        vm.prank(holder);
        assertTrue(token.approve(holder, 1));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, holder, 1));
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransfersCannotBypassBalanceChecks() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);

        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroAmountDoesNotPermitInvalidRecipientOrSpender() public {
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);

        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsExactAndIsolated(
        uint256 initialApproval,
        uint256 replacement,
        uint256 funding,
        uint256 amount
    ) public {
        funding = bound(funding, 0, SUPPLY);
        assertTrue(token.transfer(holder, funding));
        vm.startPrank(holder);
        assertTrue(token.approve(otherSpender, initialApproval));
        assertTrue(token.approve(spender, initialApproval));
        assertTrue(token.approve(spender, replacement));
        // Repeating the same approval must be idempotent, including at uint256.max.
        assertTrue(token.approve(spender, replacement));
        vm.stopPrank();
        assertEq(token.allowance(holder, spender), replacement);
        assertEq(token.allowance(holder, otherSpender), initialApproval);
        assertEq(token.balanceOf(holder), funding);

        amount = bound(amount, 0, funding < replacement ? funding : replacement);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, amount));
        assertEq(
            token.allowance(holder, spender), replacement == type(uint256).max ? replacement : replacement - amount
        );
        assertEq(token.allowance(holder, otherSpender), initialApproval);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(holder), funding - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevokingUnlimitedApprovalStopsSpendingAndAllowsReapproval(uint256 funding) public {
        funding = bound(funding, 1, SUPPLY);
        assertTrue(token.transfer(holder, funding));
        vm.startPrank(holder);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), funding);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(holder);
        assertTrue(token.approve(spender, funding));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, funding));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), funding);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalancePreservesFiniteOrInfiniteAllowance(
        uint256 funding,
        uint256 amount,
        bool unlimited
    ) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, funding + 1, type(uint256).max - 1);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.transfer(holder, funding));
        vm.prank(holder);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, funding, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.balanceOf(holder), funding);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);

        // The rejected spend must neither consume authorization nor freeze a later valid spend.
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, funding));
        assertEq(token.allowance(holder, spender), unlimited ? approved : approved - funding);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidReceiverRollsBackApprovalConsumption(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), recipient, amount));
        assertEq(token.allowance(address(this), spender), unlimited ? approved : 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripPreservesBalancesAndApprovals(uint256 funding, uint256 amount, uint256 approval)
        public
    {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, 0, funding);
        assertTrue(token.transfer(holder, funding));
        vm.prank(holder);
        assertTrue(token.approve(spender, approval));

        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), funding - amount);
        assertEq(token.balanceOf(recipient), amount);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), funding);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.allowance(recipient, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransfersMatchOneTransfer(uint256 first, uint256 second, uint256 approval) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        uint256 combined = first + second;
        approval = bound(approval, combined, type(uint256).max);
        QuantumCanary singleTransferToken = new QuantumCanary();
        assertTrue(token.approve(spender, approval));
        assertTrue(singleTransferToken.approve(spender, approval));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), holder, first));
        assertTrue(token.transferFrom(address(this), holder, second));
        assertTrue(singleTransferToken.transferFrom(address(this), holder, combined));
        vm.stopPrank();

        assertEq(token.balanceOf(holder), combined);
        assertEq(token.balanceOf(address(this)), SUPPLY - combined);
        assertEq(token.balanceOf(holder), singleTransferToken.balanceOf(holder));
        assertEq(token.balanceOf(address(this)), singleTransferToken.balanceOf(address(this)));
        assertEq(
            token.allowance(address(this), spender), approval == type(uint256).max ? approval : approval - combined
        );
        assertEq(token.allowance(address(this), spender), singleTransferToken.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(singleTransferToken.totalSupply(), SUPPLY);
    }
}
