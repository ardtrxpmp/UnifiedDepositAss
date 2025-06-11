// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Interface for the target contract
interface ITargetContract {
    function depositUSDC(uint256 amount) external;
    
    // Events
    event USDCDeposited(address indexed user, uint256 amount, uint256 timestamp);
}

// Interface for USDC token
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract DepositUSDCScript is Script {
    // Contract address
    address constant TARGET_CONTRACT = 0xe00e46e0061bF52c503ef7189fb9499ab54e31c8;
    
    // USDC token addresses (update based on your network)
    // Ethereum Mainnet USDC: 0xA0b86a33E6441E2a4c28C3b2A7b7B8C7da1B2d3e
    // Polygon USDC: 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
    // Arbitrum USDC: 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
    address constant USDC_TOKEN = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d; 
    
    function run() external {
        // Get private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        console.log("Target contract:", TARGET_CONTRACT);
        console.log("USDC token:", USDC_TOKEN);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Initialize contract interfaces
        ITargetContract targetContract = ITargetContract(TARGET_CONTRACT);
        IERC20 usdcToken = IERC20(USDC_TOKEN);
        
        // Amount to deposit (in USDC units - 6 decimals)
        // Example: 100 USDC = 100 * 10^6 = 100000000
        uint256 depositAmount = 2 * 10**6; // 2 USDC
        
        console.log("Deposit amount:", depositAmount);
        
        // Check current USDC balance
        uint256 currentBalance = usdcToken.balanceOf(deployer);
        console.log("Current USDC balance:", currentBalance);
        
        require(currentBalance >= depositAmount, "Insufficient USDC balance");
        
        // Check current allowance
        uint256 currentAllowance = usdcToken.allowance(deployer, TARGET_CONTRACT);
        console.log("Current allowance:", currentAllowance);
        
        // Approve USDC spending if needed
        if (currentAllowance < depositAmount) {
            console.log("Approving USDC spending...");
            bool approvalSuccess = usdcToken.approve(TARGET_CONTRACT, depositAmount);
            require(approvalSuccess, "USDC approval failed");
            console.log("USDC approval successful");
        }
        
        // Call the depositUSDC function
        console.log("Calling depositUSDC...");
        targetContract.depositUSDC(depositAmount);
        console.log("depositUSDC call successful!");
        
        vm.stopBroadcast();
    }
    
    // Alternative function to deposit a custom amount
    function depositCustomAmount(uint256 amount) external {
        uint256 deployerPrivateKey = 0xf6f73ae67dc21298b3aac0c161f6013ce47b4efcfb4dc4941b5c9ed01c2ccf5c;
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        ITargetContract targetContract = ITargetContract(TARGET_CONTRACT);
        IERC20 usdcToken = IERC20(USDC_TOKEN);
        
        // Check balance and allowance
        require(usdcToken.balanceOf(deployer) >= amount, "Insufficient balance");
        
        uint256 currentAllowance = usdcToken.allowance(deployer, TARGET_CONTRACT);
        if (currentAllowance < amount) {
            usdcToken.approve(TARGET_CONTRACT, amount);
        }
        
        targetContract.depositUSDC(amount);
        
        vm.stopBroadcast();
    }
}