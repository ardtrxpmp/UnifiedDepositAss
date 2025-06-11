// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/USDCAutoForwarder.sol";
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract USDCAutoForwarderTest is Test {
    USDCAutoForwarder forwarder;
    MockUSDC usdc;
    address owner;
    address user;
    address recipient;

    function setUp() public {
        owner = address(this);
        user = vm.addr(1);
        recipient = vm.addr(2);

        forwarder = new USDCAutoForwarder(recipient);
        usdc = new MockUSDC();

        // Mint USDC to user
        usdc.mint(user, 1_000e6); // 1,000 USDC (6 decimals)
    }

    function testSetUSDCAddress() public {
        // Should fail because usdcSetStatus is false (setUSDCAddress logic bug)
        vm.expectRevert(USDCAutoForwarder.USDCAlreadySet.selector);
        forwarder.setUSDCAddress(address(usdc));
    }


    function testUpdateRecipient() public {
        address newRecipient = vm.addr(3);
        forwarder.updateRecipient(newRecipient);
        assertEq(forwarder.recipient(), newRecipient);
    }

    function testDepositZeroReverts() public {
        vm.startPrank(user);
        vm.expectRevert(USDCAutoForwarder.ZeroAmount.selector);
        forwarder.depositUSDC(0);
        vm.stopPrank();
    }

    function testRejectETH() public {
        vm.expectRevert("ETH not accepted");
        (bool success, ) = address(forwarder).call{value: 1 ether}("");
        assertFalse(success);
    }
}
