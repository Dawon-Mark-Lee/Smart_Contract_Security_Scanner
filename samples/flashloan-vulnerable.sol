// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
}

interface ILendingPool {
    function getReserveData(address asset) external view returns (uint256 totalLiquidity, uint256 utilizationRate);
}

/**
 * @title VulnerableFlashloanDEX
 * @dev A DEX contract with multiple vulnerabilities related to flashloan attacks
 * @notice This contract demonstrates various MEV and flashloan attack vectors
 */
contract VulnerableFlashloanDEX {
    mapping(address => uint256) public liquidity;
    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => uint256) public totalSupply;
    
    IPriceOracle public priceOracle;
    ILendingPool public lendingPool;
    IERC20 public tokenA;
    IERC20 public tokenB;
    
    address public owner;
    uint256 public feeRate = 30; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed provider, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed provider, uint256 amountA, uint256 amountB);
    event PriceUpdate(address indexed token, uint256 newPrice);
    
    constructor(address _tokenA, address _tokenB, address _oracle, address _lendingPool) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        priceOracle = IPriceOracle(_oracle);
        lendingPool = ILendingPool(_lendingPool);
        owner = msg.sender;
    }
    
    // VULNERABILITY: Price manipulation via flashloan
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external {
        require(amountIn > 0, "Invalid amount");
        
        // VULNERABILITY: Using spot price from oracle without TWAP
        uint256 priceIn = priceOracle.getPrice(tokenIn);
        uint256 priceOut = priceOracle.getPrice(tokenOut);
        
        // VULNERABILITY: Simple price calculation susceptible to manipulation
        uint256 amountOut = (amountIn * priceIn) / priceOut;
        
        // VULNERABILITY: No slippage protection
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }
    
    // VULNERABILITY: AMM price calculation using reserves (flashloan manipulable)
    function swapWithAMM(uint256 amountAIn) external {
        require(amountAIn > 0, "Invalid amount");
        
        uint256 reserveA = tokenA.balanceOf(address(this));
        uint256 reserveB = tokenB.balanceOf(address(this));
        
        // VULNERABILITY: Using current reserves for price calculation
        // Can be manipulated within a single transaction via flashloan
        uint256 amountBOut = getAmountOut(amountAIn, reserveA, reserveB);
        
        tokenA.transferFrom(msg.sender, address(this), amountAIn);
        tokenB.transfer(msg.sender, amountBOut);
        
        emit Swap(msg.sender, address(tokenA), address(tokenB), amountAIn, amountBOut);
    }
    
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) 
        internal view returns (uint256) {
        // VULNERABILITY: Constant product formula without protection
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - feeRate);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        return numerator / denominator;
    }
    
    // VULNERABILITY: Front-running vulnerable function
    function buyAtMaxPrice(uint256 amount, uint256 maxPrice) external {
        uint256 currentPrice = getCurrentPrice();
        require(currentPrice <= maxPrice, "Price too high");
        
        // VULNERABILITY: Price check and execution in same transaction
        // Can be front-run by MEV bots
        executePurchase(amount, currentPrice);
    }
    
    function getCurrentPrice() public view returns (uint256) {
        // VULNERABILITY: Weak randomness using block properties
        uint256 basePrice = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            block.prevrandao, 
            blockhash(block.number - 1)
        ))) % 1000;
        
        // VULNERABILITY: Price depends on easily manipulable block data
        return basePrice + 100; // Base price + premium
    }
    
    function executePurchase(uint256 amount, uint256 price) internal {
        // VULNERABILITY: Missing input validation
        userBalances[msg.sender][address(tokenA)] += amount;
        
        // VULNERABILITY: Unsafe external call without return check
        tokenB.transfer(msg.sender, amount * price);
    }
    
    // VULNERABILITY: Governance attack via flashloan
    mapping(address => uint256) public votingPower;
    mapping(bytes32 => uint256) public proposals;
    
    function vote(bytes32 proposalId, uint256 weight) external {
        // VULNERABILITY: Voting power based on current balance
        // Can be inflated via flashloan within same transaction
        uint256 balance = tokenA.balanceOf(msg.sender);
        votingPower[msg.sender] = balance;
        
        proposals[proposalId] += weight * balance;
    }
    
    // VULNERABILITY: Liquidation mechanism susceptible to price manipulation
    struct Position {
        uint256 collateral;
        uint256 debt;
        address owner;
    }
    
    mapping(uint256 => Position) public positions;
    uint256 public positionCounter;
    uint256 public constant LIQUIDATION_THRESHOLD = 150; // 150%
    
    function liquidate(uint256 positionId) public {
        Position storage position = positions[positionId];
        
        // VULNERABILITY: Using current oracle price for liquidation
        // Price can be manipulated via flashloan to trigger false liquidations
        uint256 collateralValue = position.collateral * priceOracle.getPrice(address(tokenA));
        uint256 debtValue = position.debt * priceOracle.getPrice(address(tokenB));
        
        uint256 collateralizationRatio = (collateralValue * 100) / debtValue;
        
        require(collateralizationRatio < LIQUIDATION_THRESHOLD, "Position healthy");
        
        // VULNERABILITY: No liquidation penalty or partial liquidation
        userBalances[msg.sender][address(tokenA)] += position.collateral;
        delete positions[positionId];
    }
    
    // VULNERABILITY: Oracle manipulation via lending pool data
    function updatePriceFromLending(address token) external {
        // VULNERABILITY: Using lending pool utilization for price
        // Can be manipulated by large borrows/deposits
        (, uint256 utilizationRate) = lendingPool.getReserveData(token);
        
        // Higher utilization = higher price (flawed logic)
        uint256 newPrice = (utilizationRate * 100) / 1e18;
        
        // VULNERABILITY: Anyone can update price
        // VULNERABILITY: No validation of price change magnitude
        emit PriceUpdate(token, newPrice);
    }
    
    // VULNERABILITY: Sandwich attack vulnerable AMM function
    function addLiquidity(uint256 amountA, uint256 amountB) external {
        // VULNERABILITY: No deadline protection
        // VULNERABILITY: No slippage protection
        
        uint256 reserveA = tokenA.balanceOf(address(this));
        uint256 reserveB = tokenB.balanceOf(address(this));
        
        if (reserveA == 0 && reserveB == 0) {
            // First liquidity provider
            liquidity[msg.sender] = amountA * amountB;
        } else {
            // VULNERABILITY: Ratio calculation without considering market impact
            uint256 optimalB = (amountA * reserveB) / reserveA;
            require(amountB >= optimalB, "Insufficient B amount");
            
            uint256 liquidityMinted = (amountA * totalSupply[address(this)]) / reserveA;
            liquidity[msg.sender] += liquidityMinted;
        }
        
        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);
        
        emit LiquidityAdded(msg.sender, amountA, amountB);
    }
    
    // VULNERABILITY: MEV extractable arbitrage function
    function arbitrage() external {
        uint256 reserveA = tokenA.balanceOf(address(this));
        uint256 reserveB = tokenB.balanceOf(address(this));
        
        // VULNERABILITY: Predictable arbitrage calculation
        // MEV bots can front-run this function
        uint256 oraclePrice = priceOracle.getPrice(address(tokenA));
        uint256 poolPrice = (reserveB * 1e18) / reserveA;
        
        if (oraclePrice > poolPrice) {
            // Buy from pool, sell to oracle
            uint256 arbitrageAmount = (oraclePrice - poolPrice) * reserveA / 1e18;
            
            // VULNERABILITY: No access control on arbitrage profits
            tokenA.transfer(msg.sender, arbitrageAmount);
        }
    }
    
    // VULNERABILITY: Time-based functions susceptible to timestamp manipulation
    mapping(address => uint256) public lastAction;
    uint256 public constant COOLDOWN_PERIOD = 1 hours;
    
    function performTimedAction() external {
        // VULNERABILITY: Miners can manipulate block.timestamp
        require(block.timestamp >= lastAction[msg.sender] + COOLDOWN_PERIOD, "Cooldown active");
        
        lastAction[msg.sender] = block.timestamp;
        
        // Give reward based on timestamp
        uint256 reward = block.timestamp % 1000;
        tokenA.transfer(msg.sender, reward);
    }
    
    // VULNERABILITY: Centralized control susceptible to admin key compromise
    function emergencyDrain() external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: No timelock or multi-sig protection
        // VULNERABILITY: No emergency conditions check
        uint256 balanceA = tokenA.balanceOf(address(this));
        uint256 balanceB = tokenB.balanceOf(address(this));
        
        tokenA.transfer(owner, balanceA);
        tokenB.transfer(owner, balanceB);
    }
    
    // VULNERABILITY: Signature replay attack
    mapping(address => uint256) public nonces;
    
    function executeWithSignature(
        address user,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "Signature expired");
        
        // VULNERABILITY: No nonce usage - signature can be replayed
        bytes32 hash = keccak256(abi.encodePacked(user, amount, deadline));
        address signer = ecrecover(hash, v, r, s);
        require(signer == user, "Invalid signature");
        
        // VULNERABILITY: No protection against replay attacks across different chains
        tokenA.transfer(user, amount);
    }
    
    // VULNERABILITY: Delegate call to untrusted contracts
    function proxyCall(address target, bytes calldata data) external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: Delegatecall executes in the context of this contract
        // Malicious target can modify storage variables
        (bool success, ) = target.delegatecall(data);
        require(success, "Delegatecall failed");
    }
    
    // VULNERABILITY: Unchecked low-level calls
    function batchExecute(address[] calldata targets, bytes[] calldata calls) external {
        require(msg.sender == owner, "Only owner");
        require(targets.length == calls.length, "Array mismatch");
        
        for (uint256 i = 0; i < targets.length; i++) {
            // VULNERABILITY: No check if target is a contract
            // VULNERABILITY: Unchecked return value
            (bool success, ) = targets[i].call(calls[i]);
            require(success, "Low-level call failed");
        }
    }
    
    // VULNERABILITY: Integer overflow in fee calculation (if using older Solidity)
    function calculateFeeWithBonus(uint256 amount, uint256 bonus) external view returns (uint256) {
        // VULNERABILITY: In older Solidity versions, this could overflow
        uint256 fee = amount * feeRate / FEE_DENOMINATOR;
        return fee + bonus; // Potential overflow
    }
    
    // VULNERABILITY: DoS via gas griefing
    address[] public registeredUsers;
    
    function distributeRewards() external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: Unbounded loop can run out of gas
        // VULNERABILITY: External calls in loop can be griefed
        for (uint256 i = 0; i < registeredUsers.length; i++) {
            address user = registeredUsers[i];
            uint256 reward = calculateUserReward(user);
            
            // VULNERABILITY: External call can revert and DoS the entire function
            tokenA.transfer(user, reward);
        }
    }
    
    function calculateUserReward(address user) internal view returns (uint256) {
        return userBalances[user][address(tokenA)] / 100; // 1% reward
    }
    
    // VULNERABILITY: Missing access control on critical functions
    function setFeeRate(uint256 newFeeRate) external {
        // VULNERABILITY: Anyone can change fee rate
        feeRate = newFeeRate;
    }
    
    function setOracle(address newOracle) external {
        // VULNERABILITY: No access control on oracle changes
        priceOracle = IPriceOracle(newOracle);
    }
    
    // VULNERABILITY: State variable shadowing
    function processUserBalance(uint256 amount) external {
        // Directly update the state variable mapping
        userBalances[msg.sender][address(tokenA)] = amount;
    }
    
    // VULNERABILITY: Insufficient event logging
    function criticalStateChange(address newOwner, uint256 /* newLimit */) external {
        require(msg.sender == owner, "Only owner");
        
        // VULNERABILITY: No events emitted for critical changes
        owner = newOwner;
        // Missing event emission
    }
    
    // VULNERABILITY: Race condition in withdrawal
    mapping(address => bool) public pendingWithdrawals;
    
    function initiateWithdrawal(uint256 amount) external {
        require(!pendingWithdrawals[msg.sender], "Withdrawal pending");
        require(userBalances[msg.sender][address(tokenA)] >= amount, "Insufficient balance");
        
        pendingWithdrawals[msg.sender] = true;
        
        // VULNERABILITY: State change after setting flag
        // Another transaction could interfere
        userBalances[msg.sender][address(tokenA)] -= amount;
        tokenA.transfer(msg.sender, amount);
        
        pendingWithdrawals[msg.sender] = false;
    }
    
    // VULNERABILITY: Frontrunning via MEV
    function limitOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external {
        uint256 currentRate = getExchangeRate(tokenIn, tokenOut);
        uint256 expectedOut = amountIn * currentRate / 1e18;
        
        require(expectedOut >= minAmountOut, "Slippage too high");
        
        // VULNERABILITY: Time gap between check and execution
        // Price can change due to frontrunning
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, expectedOut);
    }
    
    function getExchangeRate(address tokenIn, address tokenOut) internal view returns (uint256) {
        // VULNERABILITY: Using spot prices
        return priceOracle.getPrice(tokenOut) * 1e18 / priceOracle.getPrice(tokenIn);
    }
    
    // VULNERABILITY: Lack of circuit breakers
    function massLiquidation(uint256[] calldata positionIds) external {
        // VULNERABILITY: No limits on batch operations
        // Can cause extreme market impact
        for (uint256 i = 0; i < positionIds.length; i++) {
            liquidate(positionIds[i]);
        }
    }
    
    // View functions (some with vulnerabilities)
    function getReserves() external view returns (uint256 reserveA, uint256 reserveB) {
        return (tokenA.balanceOf(address(this)), tokenB.balanceOf(address(this)));
    }
    
    function getUserBalance(address user, address token) external view returns (uint256) {
        return userBalances[user][token];
    }
    
    // VULNERABILITY: Information leakage
    function getOwnerPrivateData() external view returns (address, uint256) {
        // VULNERABILITY: Exposing internal contract state
        return (owner, address(this).balance);
    }
    
    // VULNERABILITY: No receive/fallback protection
    receive() external payable {
        // VULNERABILITY: Accepting arbitrary ETH without handling
    }
    
    fallback() external payable {
        // VULNERABILITY: Fallback accepts calls and ETH
    }
}