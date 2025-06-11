// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/USDCAutoForwarder.sol";
import "forge-std/console.sol";
import "forge-std/Script.sol";

/**
 * @title MultiChainDeploymentScript
 * @dev Script to deploy USDCAutoForwarder at the same deterministic address across multiple chains
 */
contract MultiChainDeploymentScript is Script {
    // Configuration struct for each chain
    struct ChainConfig {
        uint256 chainId;
        string name;
        address usdcToken;
        address recipient;
    }

    // Events
    event ContractDeployed(
        uint256 indexed chainId,
        string chainName,
        address indexed contractAddress,
        bytes32 indexed salt,
        address deployer
    );

    event USDCAddressSet(
        uint256 indexed chainId,
        address indexed contractAddress,
        address indexed usdcToken
    );

    // Constants
    bytes32 public constant DEPLOYMENT_SALT = 0x0000000000000000000000000000000000000000000000000000000000000006;

    // Chain configurations
    function getChainConfigs() internal pure returns (ChainConfig[] memory) {
        ChainConfig[] memory configs = new ChainConfig[](3);

        // Arbitrum Sepolia Testnet
        configs[0] = ChainConfig({
            chainId: 421614,
            name: "Arbitrum Sepolia",
            usdcToken: 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d, // USDC.e on Arbitrum Sepolia (bridged from Ethereum Sepolia)
            recipient: 0xF8591FaFE75eE95499D0169E2d19142f27de6542
        });

        // Optimism Sepolia Testnet
        configs[1] = ChainConfig({
            chainId: 11155420,
            name: "Optimism Sepolia",
            usdcToken: 0x5fd84259d66Cd46123540766Be93DFE6D43130D7, // USDC on Optimism Sepolia
            recipient: 0xF8591FaFE75eE95499D0169E2d19142f27de6542
        });

        // Base Sepolia Testnet
        configs[2] = ChainConfig({
            chainId: 84532,
            name: "Base Sepolia",
            usdcToken: 0x036CbD53842c5426634e7929541eC2318f3dCF7e, // USDC on Base Sepolia
            recipient: 0xF8591FaFE75eE95499D0169E2d19142f27de6542
        });

        return configs;
    }

    function run() external {
        // Get current chain ID
        uint256 currentChainId = block.chainid;
        console.log("Current Chain ID:", currentChainId);

        // Get configurations
        ChainConfig[] memory configs = getChainConfigs();

        // Find configuration for current chain
        ChainConfig memory currentConfig;
        bool found = false;

        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].chainId == currentChainId) {
                currentConfig = configs[i];
                found = true;
                break;
            }
        }

        require(found, "Chain configuration not found for current chain");

        console.log("Deploying on:", currentConfig.name);
        console.log("USDC Token:", currentConfig.usdcToken);
        console.log("Recipient:", currentConfig.recipient);

        // Deploy the contract
        address deployedAddress = deployForwarder(DEPLOYMENT_SALT, currentConfig.recipient);

        // Set USDC address after deployment (must be done by the same account that deployed)
        setUSDCAddress(payable(deployedAddress), currentConfig.usdcToken);

        // Verify the address is the same across all chains
        console.log("\n=== Address Verification ===");
        for (uint256 i = 0; i < configs.length; i++) {
            address predictedAddress = computeAddress(DEPLOYMENT_SALT, configs[i].recipient, msg.sender);

            if (configs[i].chainId == currentChainId) {
                console.log(configs[i].name, "- Deployed at:", predictedAddress);
            } else {
                console.log(configs[i].name, "- Will deploy at:", predictedAddress);
            }
        }

        console.log("\n=== Deployment Complete ===");
        console.log("Contract Address:", deployedAddress);
        console.log("USDC Token Set:", currentConfig.usdcToken);
        console.log("Recipient:", currentConfig.recipient);
    }

    /**
     * @dev Deploys USDCAutoForwarder using CREATE2 for deterministic address
     */
    function deployForwarder(bytes32 salt, address recipient) public returns (address deployed) {
        // Check if contract already exists first (before starting broadcast)
        address predictedAddress = computeAddress(salt, recipient, msg.sender);

        if (predictedAddress.code.length > 0) {
            console.log("Contract already deployed at:", predictedAddress);
            return predictedAddress;
        }

        vm.startBroadcast();

        // Deploy using CREATE2 (only recipient in constructor now)
        // msg.sender will be the owner due to Ownable(msg.sender) in constructor
        deployed = address(new USDCAutoForwarder{salt: salt}(recipient));

        console.log("Contract deployed at:", deployed);
        console.log("Contract owner will be:", msg.sender);
        console.log("Gas used for deployment:", gasleft());

        vm.stopBroadcast();

        emit ContractDeployed(block.chainid, "Current Chain", deployed, salt, msg.sender);

        return deployed;
    }

    /**
     * @dev Sets the USDC address after deployment
     */
    function setUSDCAddress(address payable contractAddress, address usdcToken) public {
        USDCAutoForwarder forwarder = USDCAutoForwarder(payable(contractAddress));
        
        // Check if USDC address is already set
        try forwarder.usdc() returns (IERC20 currentUsdc) {
            if (address(currentUsdc) != address(0)) {
                console.log("USDC address already set to:", address(currentUsdc));
                return;
            }
        } catch {
            // USDC not set yet, continue
        }

        // Verify we are the owner before attempting to set USDC address
        address contractOwner = forwarder.owner();
        address currentSender = msg.sender;
        console.log("Contract owner:", contractOwner);
        console.log("Current sender:", currentSender);
        

        vm.startBroadcast();
        
        // Set USDC address
        forwarder.setUSDCAddress(usdcToken);
        console.log("USDC address set to:", usdcToken);

        vm.stopBroadcast();

        emit USDCAddressSet(block.chainid, contractAddress, usdcToken);
    }

    /**
     * @dev Computes the deterministic address where a contract will be deployed
     * @notice Updated to only use recipient since USDC is set after deployment
     */
    function computeAddress(bytes32 salt, address recipient, address deployer) public pure returns (address predicted) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                keccak256(abi.encodePacked(type(USDCAutoForwarder).creationCode, abi.encode(recipient)))
            )
        );
        predicted = address(uint160(uint256(hash)));
    }

    /**
     * @dev Utility function to verify deployment across all chains
     */
    function verifyAllChainAddresses() external view {
        ChainConfig[] memory configs = getChainConfigs();

        console.log("\n=== All Chain Addresses ===");
        for (uint256 i = 0; i < configs.length; i++) {
            address predictedAddress = computeAddress(DEPLOYMENT_SALT, configs[i].recipient, msg.sender);
            console.log(configs[i].name, ":", predictedAddress);
        }
    }

    /**
     * @dev Get deployment information for a specific chain
     */
    function getDeploymentInfo(uint256 chainId)
        external
        view
        returns (string memory chainName, address usdcToken, address recipient, address predictedAddress)
    {
        ChainConfig[] memory configs = getChainConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].chainId == chainId) {
                chainName = configs[i].name;
                usdcToken = configs[i].usdcToken;
                recipient = configs[i].recipient;
                predictedAddress = computeAddress(DEPLOYMENT_SALT, recipient, msg.sender);
                return (chainName, usdcToken, recipient, predictedAddress);
            }
        }
        revert("Chain not supported");
    }

    /**
     * @dev Deploy on all configured chains (for testing purposes)
     * @notice This is a utility function for testing cross-chain deployment
     */
    function deployOnAllChains() external {
        ChainConfig[] memory configs = getChainConfigs();
        
        console.log("\n=== Deploying on All Chains ===");
        for (uint256 i = 0; i < configs.length; i++) {
            console.log("\nChain:", configs[i].name);
            
            // Note: This would require switching networks manually in practice
            // This is just for address calculation verification
            address predictedAddress = computeAddress(DEPLOYMENT_SALT, configs[i].recipient, msg.sender);
            console.log("Will deploy at:", predictedAddress);
            console.log("USDC Token:", configs[i].usdcToken);
            console.log("Recipient:", configs[i].recipient);
        }
    }

    /**
     * @dev Verify contract state after deployment
     */
    function verifyContractState(address payable contractAddress) external view {
        USDCAutoForwarder forwarder = USDCAutoForwarder(payable(contractAddress));
        
        console.log("\n=== Contract State Verification ===");
        console.log("Contract Address:", contractAddress);
        console.log("Owner:", forwarder.owner());
        console.log("Recipient:", forwarder.recipient());
        console.log("USDC Address:", address(forwarder.usdc()));
        console.log("USDC Set Status:", forwarder.usdcSetStatus());
        console.log("Current Balance:", forwarder.getBalance());
    }

    /**
     * @dev Emergency function to update recipient if needed
     */
    function updateRecipient(address payable  contractAddress, address newRecipient) external {
        vm.startBroadcast();
        
        USDCAutoForwarder forwarder = USDCAutoForwarder(payable(contractAddress));
        forwarder.updateRecipient(newRecipient);
        
        console.log("Recipient updated to:", newRecipient);
        
        vm.stopBroadcast();
    }
}