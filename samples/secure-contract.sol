// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/Pausable.sol";
import "../node_modules/@openzeppelin/contracts/utils/Address.sol";

/**
 * @title SecureContract
 * @dev A secure implementation following best practices
 * @notice This contract demonstrates proper security patterns
 */
contract SecureContract is ReentrancyGuard, Ownable, Pausable {
    using Address for address payable;
    
    mapping(address => uint256) private balances;
    mapping(address => bool) public authorizedUsers;
    
    uint256 public totalSupply = 1000000;
    uint256 public constant MAX_SUPPLY = 10000000;
    uint256 private nonce = 0;
    
    // Events for transparency
    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event AuthorizationChanged(address indexed user, bool authorized);
    event OwnershipTransferInitiated(address indexed newOwner);
    
    // Custom errors for gas efficiency
    error InsufficientBalance(uint256 requested, uint256 available);
    error ZeroAddressNotAllowed();
    error ExceedsMaxSupply(uint256 requested, uint256 maxAllowed);
    error NotAuthorized(address caller);
    error InvalidAmount(uint256 amount);
    
    constructor() Ownable(msg.sender) {
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    /**
     * @dev Secure deposit function with proper checks
     */
    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert InvalidAmount(msg.value);
        
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    
    /**
     * @dev Secure withdrawal with reentrancy protection
     */
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount(amount);
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance(amount, balances[msg.sender]);
        }
        
        // CEI Pattern: Checks, Effects, Interactions
        balances[msg.sender] -= amount; // Effect first
        
        // Safe interaction last
        payable(msg.sender).sendValue(amount);
        
        emit Withdrawal(msg.sender, amount);
    }
    
    /**
     * @dev Secure transfer with zero address protection
     */
    function transfer(address to, uint256 amount) external whenNotPaused {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert InvalidAmount(amount);
        if (balances[msg.sender] < amount) {
            revert InsufficientBalance(amount, balances[msg.sender]);
        }
        
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        emit Transfer(msg.sender, to, amount);
    }
    
    /**
     * @dev Secure random number generation using commit-reveal
     */
    mapping(address => bytes32) private commitments;
    mapping(address => uint256) private commitTimestamps;
    
    function commitRandomness(bytes32 commitment) external {
        commitments[msg.sender] = commitment;
        commitTimestamps[msg.sender] = block.timestamp;
    }
    
    function revealRandomness(uint256 secret) external view returns (uint256) {
        require(commitments[msg.sender] != 0, "No commitment found");
        require(
            block.timestamp > commitTimestamps[msg.sender] + 1 minutes,
            "Reveal too early"
        );
        require(
            keccak256(abi.encodePacked(secret)) == commitments[msg.sender],
            "Invalid secret"
        );
        
        // More secure randomness combining multiple sources
        return uint256(keccak256(abi.encodePacked(
            secret,
            blockhash(block.number - 1),
            block.timestamp,
            msg.sender
        ))) % 100;
    }
    
    /**
     * @dev Protected owner functions with proper access control
     */
    function setAuthorization(address user, bool authorized) external onlyOwner {
        if (user == address(0)) revert ZeroAddressNotAllowed();
        
        authorizedUsers[user] = authorized;
        emit AuthorizationChanged(user, authorized);
    }
    
    /**
     * @dev Emergency functions with proper protection
     */
    function emergencyWithdraw() external onlyOwner whenPaused {
        uint256 balance = address(this).balance;
        payable(owner()).sendValue(balance);
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev Secure minting with supply cap
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert InvalidAmount(amount);
        
        uint256 newSupply = totalSupply + amount;
        if (newSupply > MAX_SUPPLY) {
            revert ExceedsMaxSupply(newSupply, MAX_SUPPLY);
        }
        
        balances[to] += amount;
        totalSupply = newSupply;
        
        emit Transfer(address(0), to, amount);
    }
    
    /**
     * @dev Secure batch operations with gas limits
     */
    function batchTransfer(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external whenNotPaused {
        require(recipients.length == amounts.length, "Array length mismatch");
        require(recipients.length <= 100, "Too many recipients"); // Gas limit protection
        
        uint256 totalAmount = 0;
        
        // Calculate total first
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        if (balances[msg.sender] < totalAmount) {
            revert InsufficientBalance(totalAmount, balances[msg.sender]);
        }
        
        // Perform transfers
        balances[msg.sender] -= totalAmount;
        
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddressNotAllowed();
            if (amounts[i] == 0) continue; // Skip zero amounts
            
            balances[recipients[i]] += amounts[i];
            emit Transfer(msg.sender, recipients[i], amounts[i]);
        }
    }
    
    /**
     * @dev Secure price oracle pattern (example)
     */
    uint256 private lastPriceUpdate;
    uint256 private price;
    uint256 private constant PRICE_VALIDITY_PERIOD = 1 hours;
    
    function updatePrice(uint256 newPrice) external {
        require(authorizedUsers[msg.sender], "Not authorized");
        require(newPrice > 0, "Invalid price");
        
        price = newPrice;
        lastPriceUpdate = block.timestamp;
    }
    
    function getPrice() external view returns (uint256) {
        require(
            block.timestamp <= lastPriceUpdate + PRICE_VALIDITY_PERIOD,
            "Price data stale"
        );
        return price;
    }
    
    /**
     * @dev View functions for balance checking
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Secure ownership transfer with two-step process
     */
    address private pendingOwner;
    
    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0)) revert ZeroAddressNotAllowed();
        
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(newOwner);
    }
    
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Not pending owner");
        
        _transferOwnership(pendingOwner);
        pendingOwner = address(0);
    }
    
    /**
     * @dev Secure external call pattern
     */
    function safeExternalCall(
        address target,
        bytes calldata data,
        uint256 value
    ) external onlyOwner returns (bool success, bytes memory returnData) {
        require(target != address(this), "Cannot call self");
        require(authorizedUsers[target], "Target not authorized");
        
        // Use low-level call with proper error handling
        (success, returnData) = target.call{value: value}(data);
        
        // Don't revert on failure, let caller handle it
        return (success, returnData);
    }
    
    /**
     * @dev Input validation helpers
     */
    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddressNotAllowed();
        _;
    }
    
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert InvalidAmount(amount);
        _;
    }
    
    modifier onlyAuthorized() {
        if (!authorizedUsers[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }
    
    /**
     * @dev Prevent accidental Ether sends
     */
    receive() external payable {
        // Only accept Ether through deposit function
        revert("Use deposit() function");
    }
    
    fallback() external payable {
        revert("Function not found");
    }
}