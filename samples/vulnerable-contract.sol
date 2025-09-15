// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VulnerableContract {
    mapping(address => uint256) public balances;
    address public owner;
    bool public locked = false;
    uint256 public totalSupply = 1000000;
    
    constructor() {
        owner = msg.sender;
        balances[owner] = totalSupply;
    }
    
    // Reentrancy vulnerability - external call before state change
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        
        // VULNERABILITY: External call before state update
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        // State change after external call - enables reentrancy!
        balances[msg.sender] -= amount;
    }
    
    // Integer overflow vulnerability (if using older Solidity)
    function deposit() external payable {
        // In older versions, this could overflow
        balances[msg.sender] += msg.value;
    }
    
    // Unprotected function - anyone can drain the contract
    function emergencyWithdraw() external {
        // VULNERABILITY: No access control
        payable(owner).transfer(address(this).balance);
    }
    
    // Timestamp dependence vulnerability
    function isLotteryTime() public view returns (bool) {
        // VULNERABILITY: Miners can manipulate block.timestamp
        return block.timestamp % 2 == 0;
    }
    
    // tx.origin vulnerability
    function authorize() external {
        // VULNERABILITY: tx.origin can be exploited by malicious contracts
        require(tx.origin == owner, "Not authorized");
        locked = false;
    }
    
    // Missing zero address check
    function transfer(address to, uint256 amount) external {
        // VULNERABILITY: No check for zero address
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }
    
    // Weak randomness using block properties
    function generateRandomNumber() external view returns (uint256) {
        // VULNERABILITY: Predictable randomness
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))) % 100;
    }
    
    // Function without access control that changes critical state
    function setOwner(address newOwner) external {
        // VULNERABILITY: No access control on critical function
        owner = newOwner;
    }
    
    // Missing event emission for important state changes
    function updateBalance(address user, uint256 newBalance) external {
        // VULNERABILITY: No events emitted for transparency
        balances[user] = newBalance;
    }
    
    // DoS via unbounded loop
    address[] public users;
    
    function distributeRewards() external {
        // VULNERABILITY: Unbounded loop can hit gas limit
        for (uint256 i = 0; i < users.length; i++) {
            balances[users[i]] += 10;
        }
    }
    
    // Unsafe use of delegatecall
    function proxyCall(address target, bytes calldata data) external {
        // VULNERABILITY: Delegatecall to untrusted contract
        (bool success, ) = target.delegatecall(data);
        require(success, "Delegatecall failed");
    }
    
    // Front-running vulnerability
    function buyAtCurrentPrice() external payable {
        uint256 currentPrice = getCurrentPrice();
        require(msg.value >= currentPrice, "Insufficient payment");
        
        // VULNERABILITY: Price can be front-run
        balances[msg.sender] += msg.value / currentPrice;
    }
    
    function getCurrentPrice() public view returns (uint256) {
        // Simplified price calculation - vulnerable to manipulation
        return address(this).balance / totalSupply;
    }
    
    // Missing input validation
    function processLargeAmount(uint256 amount) external {
        // VULNERABILITY: No validation of amount parameter
        balances[msg.sender] = amount;
    }
    
    // Centralization risk - single point of failure
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    // VULNERABILITY: Too much power concentrated in owner
    function pause() external onlyOwner {
        locked = true;
    }
    
    function unpause() external onlyOwner {
        locked = false;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        balances[to] += amount;
        totalSupply += amount;
    }
    
    // Hardcoded gas limit vulnerability
    function sendEther(address payable recipient, uint256 amount) external {
        // VULNERABILITY: Hardcoded gas limit may not be sufficient
        (bool success, ) = recipient.call{value: amount, gas: 2300}("");
        require(success, "Transfer failed");
    }
    
    // State variable shadowing
    function shadowingExample() external view {
        // Example function without variable shadowing or unused variable
        // You can add logic here if needed
    }
}