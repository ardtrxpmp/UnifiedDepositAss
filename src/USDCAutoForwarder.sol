// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title USDCAutoForwarder
 * @dev A contract that receives USDC deposits and forwards it to a specified recipient on initialed backend trigger.
 * @notice This contract is designed to be deployed at the same address across multiple chains
 */
contract USDCAutoForwarder is ReentrancyGuard, Ownable {
    IERC20 public usdc;
    address public recipient;
    bool public usdcSetStatus;

    // Events
    event USDCDeposited(address indexed sender, uint256 amount, uint256 timestamp);

    event USDCForwarded(address indexed recipient, uint256 amount, uint256 timestamp);

    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    // Custom errors
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();
    error InsufficientBalance();
    error USDCAlreadySet();

    /**
     * @dev Constructor
     * @param _recipient Address that will receive forwarded USDC
     */
    constructor( address _recipient) Ownable(msg.sender) {
        if (_recipient == address(0)) revert ZeroAddress();

        recipient = _recipient;
    }

    function setUSDCAddress(address _usdcToken) external  {
        if (_usdcToken == address(0)) revert ZeroAddress();
        // if (!usdcSetStatus) revert USDCAlreadySet();
        usdc = IERC20(_usdcToken);
    }

    /**
     * @dev Deposits USDC to the contract (backend will forward automatically)
     * @param amount Amount of USDC to deposit
     */
    function depositUSDC(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Transfer USDC from sender to this contract
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        emit USDCDeposited(msg.sender, amount, block.timestamp);
    }

    /**
     * @dev Forwards USDC to recipient (called by backend service)
     * @param amount Amount to forward
     */
    function forwardUSDC(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 balance = usdc.balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        _forwardUSDC(amount);
    }

    /**
     * @dev Internal function to forward USDC to recipient
     * @param amount Amount to forward
     */
    function _forwardUSDC(uint256 amount) internal {
        require(usdc.transfer(recipient, amount), "Forward failed");
        emit USDCForwarded(recipient, amount, block.timestamp);
    }

    /**
     * @dev Updates the recipient address (only owner)
     * @param newRecipient New recipient address
     */
    function updateRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();

        address oldRecipient = recipient;
        recipient = newRecipient;

        emit RecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Returns the current USDC balance of this contract
     */
    function getBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @dev Fallback function to handle direct USDC transfers
     * @notice This requires manual triggering of forwardBalance() function
     */
    receive() external payable {
        // This contract doesn't handle ETH, revert any ETH transfers
        revert("ETH not accepted");
    }
}
