// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/**
 * @title SimpleStaking
 * @dev A basic staking contract with several vulnerabilities for educational purposes
 * @notice This contract demonstrates common DeFi vulnerabilities
 */
contract SimpleStaking {
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    
    mapping(address => uint256) public stakes;
    mapping(address => uint256) public lastUpdate;
    mapping(address => uint256) public rewards;
    
    uint256 public rewardRate = 100; // tokens per second per staked token
    uint256 public totalStaked;
    address public owner;
    
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    
    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
    }
    
    // VULNERABILITY: Missing access control - anyone can change reward rate
    function setRewardRate(uint256 _rewardRate) external {
        rewardRate = _rewardRate;
    }
    
    // VULNERABILITY: Missing input validation
    function stake(uint256 amount) external {
        // No check for amount > 0
        // No check for token approval
        
        updateReward(msg.sender);
        
        // VULNERABILITY: No check for transferFrom success
        stakingToken.transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender] += amount;
        totalStaked += amount;
        
        emit Staked(msg.sender, amount);
    }
    
    function withdraw(uint256 amount) external {
        require(stakes[msg.sender] >= amount, "Insufficient stake");
        
        updateReward(msg.sender);
        stakes[msg.sender] -= amount;
        totalStaked -= amount;
        
        // VULNERABILITY: Potential reentrancy if stakingToken has hooks
        // State changes should happen before external calls
        stakingToken.transfer(msg.sender, amount);
        
        emit Withdrawn(msg.sender, amount);
    }
    
    function claimReward() external {
        updateReward(msg.sender);
        
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        
        // VULNERABILITY: No check for contract balance
        // VULNERABILITY: No check for transfer success
        rewardToken.transfer(msg.sender, reward);
        
        emit RewardClaimed(msg.sender, reward);
    }
    
    function updateReward(address user) internal {
        if (stakes[user] > 0) {
            uint256 timeElapsed = block.timestamp - lastUpdate[user];
            // VULNERABILITY: Potential overflow in older Solidity versions
            rewards[user] += stakes[user] * rewardRate * timeElapsed;
        }
        lastUpdate[user] = block.timestamp;
    }
    
    // VULNERABILITY: Price manipulation susceptible function
    function getAPY() external view returns (uint256) {
        if (totalStaked == 0) return 0;
        
        // VULNERABILITY: Using spot balances for APY calculation
        // This can be manipulated by large deposits/withdrawals
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        return (rewardBalance * 365 days * 100) / totalStaked;
    }
    
    // VULNERABILITY: Flash loan attack vector
    function calculateReward(address user) external view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdate[user];
        
        // VULNERABILITY: Anyone can call this with current timestamp
        // Could be used in flash loan attacks to estimate rewards
        return stakes[user] * rewardRate * timeElapsed;
    }
    
    // VULNERABILITY: Centralized control without timelock
    function emergencyWithdraw() external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: Owner can drain all funds without timelock
        uint256 stakingBalance = stakingToken.balanceOf(address(this));
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        
        stakingToken.transfer(owner, stakingBalance);
        rewardToken.transfer(owner, rewardBalance);
    }
    
    // VULNERABILITY: Price oracle manipulation
    function swapRewards() external {
        updateReward(msg.sender);
        
        uint256 rewardAmount = rewards[msg.sender];
        rewards[msg.sender] = 0;
        
        // VULNERABILITY: Using potentially manipulable price source
        uint256 stakingAmount = getSwapRate() * rewardAmount;
        
        // VULNERABILITY: No slippage protection
        stakes[msg.sender] += stakingAmount;
        totalStaked += stakingAmount;
    }
    
    function getSwapRate() internal view returns (uint256) {
        // VULNERABILITY: Simplified rate calculation susceptible to manipulation
        uint256 stakingBalance = stakingToken.balanceOf(address(this));
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        
        if (rewardBalance == 0) return 0;
        return stakingBalance / rewardBalance;
    }
    
    // VULNERABILITY: DoS through gas limit
    address[] public stakers;
    
    function distributeBonus() external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: Unbounded loop can hit gas limit
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakes[stakers[i]] > 0) {
                rewards[stakers[i]] += 1000; // Fixed bonus
            }
        }
    }
    
    // VULNERABILITY: Front-running opportunity
    function announceRewardIncrease(uint256 newRate) external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: Public announcement allows front-running
        // Users can stake large amounts before rate increase
        rewardRate = newRate;
    }
    
    // VULNERABILITY: Integer precision loss
    function calculateProportionalReward(uint256 totalRewards) external view returns (uint256) {
        if (totalStaked == 0) return 0;
        
        // VULNERABILITY: Division before multiplication can cause precision loss
        return (stakes[msg.sender] / totalStaked) * totalRewards;
    }
    
    // VULNERABILITY: Timestamp dependence
    function isRewardDay() external view returns (bool) {
        // VULNERABILITY: Miners can manipulate block.timestamp
        return (block.timestamp / 1 days) % 7 == 0; // Every 7 days
    }
    
    // VULNERABILITY: Missing event emission
    function updateStake(address user, uint256 newStake) external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: Important state change without event
        uint256 oldStake = stakes[user];
        stakes[user] = newStake;
        totalStaked = totalStaked - oldStake + newStake;
    }
    
    // VULNERABILITY: Unchecked external call
    function notifyRewardAmount(uint256 reward, address notifier) external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: External call without checking if address is contract
        // Could fail silently if notifier is EOA
        (bool success, ) = notifier.call(
            abi.encodeWithSignature("onRewardNotification(uint256)", reward)
        );
        require(success, "Notifier call failed");
    }
    
    // VULNERABILITY: State variable shadowing
    function processWithdrawal(uint256 amount) external {
        require(stakes[msg.sender] >= amount, "Insufficient stake");
        
        // VULNERABILITY: Local variable shadows state variable
        address user = msg.sender;
        
        // This doesn't actually use the contract owner
        stakes[user] -= amount;
        stakingToken.transfer(user, amount);
    }
    
    // View functions
    function getStake(address user) external view returns (uint256) {
        return stakes[user];
    }
    
    function getPendingReward(address user) external view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdate[user];
        return rewards[user] + (stakes[user] * rewardRate * timeElapsed);
    }
    
    function getContractBalances() external view returns (uint256 stakingBalance, uint256 rewardBalance) {
        stakingBalance = stakingToken.balanceOf(address(this));
        rewardBalance = rewardToken.balanceOf(address(this));
    }
}