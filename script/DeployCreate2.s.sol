// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/USDCAutoForwarder.sol";
import "forge-std/console.sol";
import "forge-std/Script.sol";

/**
 * @title USDCForwarderFactory
 * @dev Factory contract to deploy USDCAutoForwarder at deterministic addresses using CREATE2
 */
contract USDCForwarderFactory is Script {
    event ContractDeployed(
        address indexed contractAddress,
        bytes32 indexed salt,
        address indexed deployer
    );

    function run() public {
        deployForwarder(
            0x0000000000000000000000000000000000000000000000000000000000000001,
            0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d, // Example USDC address on Ethereum mainnet
            0xF8591FaFE75eE95499D0169E2d19142f27de6542 // Example recipient address
        );
    }

    /**
     * @dev Deploys USDCAutoForwarder using CREATE2 for deterministic address
     * @param salt Salt for CREATE2 deployment
     * @param usdcToken Address of USDC token on the current chain
     * @param recipient Address that will receive forwarded USDC
     * @return deployed The address of the deployed contract
     */
    function deployForwarder(
        bytes32 salt,
        address usdcToken,
        address recipient
    ) public returns (address deployed) {
        // Deploy using CREATE2
        deployed = address(new USDCAutoForwarder{salt: salt}(usdcToken, recipient));
        console.log("Deployed Address::::", deployed);
        
        emit ContractDeployed(deployed, salt, msg.sender);
    }

    /**
     * @dev Computes the address where a contract will be deployed
     * @param salt Salt for CREATE2 deployment
     * @param usdcToken Address of USDC token
     * @param recipient Address that will receive forwarded USDC
     * @param deployer Address of the factory contract (this contract)
     * @return predicted The predicted address
     */
    function computeAddress(
        bytes32 salt,
        address usdcToken,
        address recipient,
        address deployer
    ) external pure returns (address predicted) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                deployer,
                salt,
                keccak256(
                    abi.encodePacked(
                        type(USDCAutoForwarder).creationCode,
                        abi.encode(usdcToken, recipient)
                    )
                )
            )
        );
        predicted = address(uint160(uint256(hash)));
    }
}