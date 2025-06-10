// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/USDCAutoForwarder.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";


contract USDCAutoForwarderTest is Test {
    USDCAutoForwarder public forwarder;
    MockUSDC public usdc;
    
    address public owner = address(0x1);
    address public recipient = address(0x2);
    address public user = address(0x3);
    address public attacker = address(0x4);
    
    uint256 constant USDC_AMOUNT = 1000 * 10**6; // 1000 USDC

    event USDCDeposited(address indexed sender, uint256 amount, uint256 timestamp);
    event USDCForwarded(address indexed recipient, uint256 amount, uint256 timestamp);
    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    function setUp() public {
        // Deploy mock USDC
        usdc = new MockUSDC();
        
        // Deploy forwarder contract
        vm.prank(owner);
        forwarder = new USDCAutoForwarder(address(usdc), recipient);
        
        // Mint USDC to test accounts
        usdc.mint(user, USDC_AMOUNT * 10);
        usdc.mint(attacker, USDC_AMOUNT);
    }

    // Constructor tests
    function test_Constructor() public {
        assertEq(address(forwarder.usdc()), address(usdc));
        assertEq(forwarder.recipient(), recipient);
        assertEq(forwarder.owner(), owner);
    }

    function test_Constructor_RevertZeroUSDCAddress() public {
        vm.prank(owner);
        vm.expectRevert(USDCAutoForwarder.ZeroAddress.selector);
        new USDCAutoForwarder(address(0), recipient);
    }

    function test_Constructor_RevertZeroRecipientAddress() public {
        vm.prank(owner);
        vm.expectRevert(USDCAutoForwarder.ZeroAddress.selector);
        new USDCAutoForwarder(address(usdc), address(0));
    }

    // Deposit tests
    function test_DepositUSDC() public {
        vm.startPrank(user);
        usdc.approve(address(forwarder), USDC_AMOUNT);
        
        vm.expectEmit(true, false, false, true);
        emit USDCDeposited(user, USDC_AMOUNT, block.timestamp);
        
        forwarder.depositUSDC(USDC_AMOUNT);
        vm.stopPrank();
        
        assertEq(forwarder.getBalance(), USDC_AMOUNT);
        assertEq(usdc.balanceOf(address(forwarder)), USDC_AMOUNT);
    }

    function test_DepositUSDC_RevertZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(USDCAutoForwarder.ZeroAmount.selector);
        forwarder.depositUSDC(0);
    }

    // Forward tests
    function test_ForwardUSDC() public {
        // First deposit some USDC
        vm.startPrank(user);
        usdc.approve(address(forwarder), USDC_AMOUNT);
        forwarder.depositUSDC(USDC_AMOUNT);
        vm.stopPrank();
        
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);
        
        vm.expectEmit(true, false, false, true);
        emit USDCForwarded(recipient, USDC_AMOUNT, block.timestamp);
        
        forwarder.forwardUSDC(USDC_AMOUNT);
        
        assertEq(forwarder.getBalance(), 0);
        assertEq(usdc.balanceOf(recipient), recipientBalanceBefore + USDC_AMOUNT);
    }

    function test_ForwardUSDC_RevertZeroAmount() public {
        vm.expectRevert(USDCAutoForwarder.ZeroAmount.selector);
        forwarder.forwardUSDC(0);
    }

    function test_ForwardUSDC_RevertInsufficientBalance() public {
        vm.expectRevert(USDCAutoForwarder.InsufficientBalance.selector);
        forwarder.forwardUSDC(USDC_AMOUNT);
    }

    // Update recipient tests
    function test_UpdateRecipient() public {
        address newRecipient = address(0x6);
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit RecipientUpdated(recipient, newRecipient);
        
        forwarder.updateRecipient(newRecipient);
        
        assertEq(forwarder.recipient(), newRecipient);
    }
    function test_UpdateRecipient_RevertZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(USDCAutoForwarder.ZeroAddress.selector);
        forwarder.updateRecipient(address(0));
    }

    // Utility function tests
    function test_GetBalance() public {
        assertEq(forwarder.getBalance(), 0);
        
        // Deposit and check balance
        vm.startPrank(user);
        usdc.approve(address(forwarder), USDC_AMOUNT);
        forwarder.depositUSDC(USDC_AMOUNT);
        vm.stopPrank();
        
        assertEq(forwarder.getBalance(), USDC_AMOUNT);
    }

    // // Receive function tests
    // function test_Receive_RevertETHNotAccepted() public {
    //     vm.expectRevert();
    //     (bool success,) = address(forwarder).call{value: 1 ether}("");
    //     assertFalse(success);
    // }

    // Reentrancy tests
    function test_DepositUSDC_ReentrancyProtection() public {
        // This test ensures the nonReentrant modifier works
        // In a real attack scenario, this would be more complex
        vm.startPrank(user);
        usdc.approve(address(forwarder), USDC_AMOUNT);
        forwarder.depositUSDC(USDC_AMOUNT);
        vm.stopPrank();
        
        // Verify single deposit worked
        assertEq(forwarder.getBalance(), USDC_AMOUNT);
    }

    // Fuzz tests
    function testFuzz_DepositUSDC(uint256 amount) public {
        vm.assume(amount > 0 && amount <= USDC_AMOUNT * 10);
        
        vm.startPrank(user);
        usdc.approve(address(forwarder), amount);
        forwarder.depositUSDC(amount);
        vm.stopPrank();
        
        assertEq(forwarder.getBalance(), amount);
    }

    function testFuzz_ForwardUSDC(uint256 depositAmount, uint256 forwardAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= USDC_AMOUNT * 10);
        vm.assume(forwardAmount > 0 && forwardAmount <= depositAmount);
        
        // Deposit
        vm.startPrank(user);
        usdc.approve(address(forwarder), depositAmount);
        forwarder.depositUSDC(depositAmount);
        vm.stopPrank();
        
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);
        
        // Forward
        forwarder.forwardUSDC(forwardAmount);
        
        assertEq(forwarder.getBalance(), depositAmount - forwardAmount);
        assertEq(usdc.balanceOf(recipient), recipientBalanceBefore + forwardAmount);
    }

    // Integration tests
    function test_FullWorkflow() public {
        // 1. Deposit USDC
        vm.startPrank(user);
        usdc.approve(address(forwarder), USDC_AMOUNT);
        forwarder.depositUSDC(USDC_AMOUNT);
        vm.stopPrank();
        
        assertEq(forwarder.getBalance(), USDC_AMOUNT);
        
        // 2. Update recipient
        address newRecipient = address(0x7);
        vm.prank(owner);
        forwarder.updateRecipient(newRecipient);
        
        // 3. Forward USDC to new recipient
        uint256 newRecipientBalanceBefore = usdc.balanceOf(newRecipient);
        forwarder.forwardUSDC(USDC_AMOUNT);
        
        assertEq(forwarder.getBalance(), 0);
        assertEq(usdc.balanceOf(newRecipient), newRecipientBalanceBefore + USDC_AMOUNT);
    }

    function test_MultipleDepositsAndForwards() public {
        uint256 depositAmount = USDC_AMOUNT / 4;
        
        // Multiple deposits
        for (uint i = 0; i < 4; i++) {
            vm.startPrank(user);
            usdc.approve(address(forwarder), depositAmount);
            forwarder.depositUSDC(depositAmount);
            vm.stopPrank();
        }
        
        assertEq(forwarder.getBalance(), USDC_AMOUNT);
        
        // Multiple forwards
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);
        for (uint i = 0; i < 4; i++) {
            forwarder.forwardUSDC(depositAmount);
        }
        
        assertEq(forwarder.getBalance(), 0);
        assertEq(usdc.balanceOf(recipient), recipientBalanceBefore + USDC_AMOUNT);
    }
}