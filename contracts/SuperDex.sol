// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

 // First Dev Community Mission: Crazy Contract Challenge 
    
    // Protocol metadata
/**
 * Monad Dev Mission 1 Completed  
 * @title Crazycassini Devnads
 * @dev A comprehensive DeFi protocol with staking, liquidity pools, and governance
 * @custom:security-contact security@monaddefi.example.com
 * https://x.com/Cassini0x  https://x.com/monad_dev 
   https://x.com/monad_dev/status/1907077431241920719 
   Discord cassini8620  
   */
contract Crazycassini is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    // Token contract
    IERC20 public immutable token;
    
    // Staking parameters
    struct Stake {
        uint128 amount;
        uint64 startTime;
        uint64 lockPeriod;
        uint128 rewards;
        bool isActive;
    }
    
    // User stakes
    mapping(address => Stake) public stakes;
    
    // Staking parameters
    uint256 public constant MIN_STAKE_AMOUNT = 100 * 10**18; // 100 tokens
    uint256 public constant MAX_STAKE_AMOUNT = 1000000 * 10**18; // 1M tokens
    uint256 public constant MIN_LOCK_PERIOD = 7 days;
    uint256 public constant MAX_LOCK_PERIOD = 365 days;
    uint256 public constant REWARD_RATE = 10; // 10% APY
    
    // Liquidity pool parameters
    struct Pool {
        address token;
        uint128 totalLiquidity;
        uint64 lastUpdateTime;
        uint32 rewardRate;
        bool isActive;
    }
    
    mapping(uint256 => Pool) public pools;
    Counters.Counter private poolCounter;
    
    // Governance parameters
    struct Proposal {
        uint64 id;
        address proposer;
        uint64 startTime;
        uint64 endTime;
        uint128 forVotes;
        uint128 againstVotes;
        bool executed;
        bool canceled;
    }
    
    mapping(uint256 => Proposal) public proposals;
    Counters.Counter private proposalCounter;
    
    // Governance configuration
    uint256 public constant PROPOSAL_THRESHOLD = 1000 ether; // Minimum stake to create proposal
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant EXECUTION_DELAY = 2 days;
    uint256 public constant MINIMUM_QUORUM = 10000 ether; // Minimum total votes required

    // Governance state
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => uint256) public proposalTotalVotes;
    mapping(uint256 => bytes) public proposalCallData;
    mapping(uint256 => address) public proposalTarget;
    
    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event PoolCreated(uint256 indexed poolId, address token);
    event LiquidityAdded(uint256 indexed poolId, address indexed user, uint256 amount);
    event LiquidityRemoved(uint256 indexed poolId, address indexed user, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address oldCollector, address newCollector);
    
    // Modifiers
    modifier onlyStaker() {
        require(stakes[msg.sender].isActive, "Not an active staker");
        _;
    }
    
    modifier validPool(uint256 poolId) {
        require(pools[poolId].isActive, "Pool does not exist");
        _;
    }
    
    modifier validProposal(uint256 proposalId) {
        require(proposals[proposalId].id == proposalId, "Proposal does not exist");
        _;
    }
    
    constructor(address _token) Ownable(0xD1f72d41c8eF5D4B18922bd6a08C85E5278B177B) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }
    
    // Staking functions
    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant whenNotPaused {
        require(amount >= MIN_STAKE_AMOUNT && amount <= MAX_STAKE_AMOUNT, "Invalid amount");
        require(lockPeriod >= MIN_LOCK_PERIOD && lockPeriod <= MAX_LOCK_PERIOD, "Invalid lock period");
        require(!stakes[msg.sender].isActive, "Already staking");
        
        token.safeTransferFrom(msg.sender, address(this), amount);
        
        stakes[msg.sender] = Stake({
            amount: uint128(amount),
            startTime: uint64(block.timestamp),
            lockPeriod: uint64(lockPeriod),
            rewards: 0,
            isActive: true
        });
        
        emit Staked(msg.sender, amount, lockPeriod);
    }
    
    function unstake() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.isActive, "Not staking");
        require(block.timestamp >= userStake.startTime + userStake.lockPeriod, "Lock period not ended");
        
        uint256 amount = userStake.amount;
        userStake.isActive = false;
        
        token.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }
    
    function claimRewards() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.isActive, "Not staking");
        
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, "No rewards to claim");
        
        userStake.rewards = 0;
        userStake.startTime = uint64(block.timestamp);
        
        token.safeTransfer(msg.sender, rewards);
        emit RewardsClaimed(msg.sender, rewards);
    }
    
    // Liquidity pool functions
    function createPool(address _token) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        
        poolCounter.increment();
        uint256 poolId = poolCounter.current();
        
        pools[poolId] = Pool({
            token: _token,
            totalLiquidity: 0,
            lastUpdateTime: uint64(block.timestamp),
            rewardRate: 5, // 5% APY
            isActive: true
        });
        
        emit PoolCreated(poolId, _token);
    }
    
    function addLiquidity(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool does not exist");
        
        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);
        pool.totalLiquidity += uint128(amount);
        pool.lastUpdateTime = uint64(block.timestamp);
        
        emit LiquidityAdded(poolId, msg.sender, amount);
    }
    
    function removeLiquidity(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = pools[poolId];
        require(pool.isActive, "Pool does not exist");
        require(amount <= pool.totalLiquidity, "Insufficient liquidity");
        
        pool.totalLiquidity -= uint128(amount);
        pool.lastUpdateTime = uint64(block.timestamp);
        
        IERC20(pool.token).safeTransfer(msg.sender, amount);
        emit LiquidityRemoved(poolId, msg.sender, amount);
    }
    
    // Governance functions
    function createProposal(
        string memory /* description */,  // Commented out unused parameter
        address target,
        bytes memory callData
    ) external nonReentrant whenNotPaused {
        require(stakes[msg.sender].amount >= PROPOSAL_THRESHOLD, "Insufficient stake");
        
        proposalCounter.increment();
        uint256 proposalId = proposalCounter.current();
        
        proposals[proposalId] = Proposal({
            id: uint64(proposalId),
            proposer: msg.sender,
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp + VOTING_PERIOD),
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            canceled: false
        });
        
        proposalTarget[proposalId] = target;
        proposalCallData[proposalId] = callData;
        
        emit ProposalCreated(proposalId, msg.sender);
    }
    
    function castVote(uint256 proposalId, bool support) external nonReentrant validProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        
        uint256 votingPower = _calculateVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");
        
        hasVoted[proposalId][msg.sender] = true;
        proposalTotalVotes[proposalId] += votingPower;
        
        if (support) {
            proposal.forVotes += uint128(votingPower);
        } else {
            proposal.againstVotes += uint128(votingPower);
        }
        
        emit Voted(proposalId, msg.sender, support, votingPower);
    }
    
    function executeProposal(uint256 proposalId) external nonReentrant validProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(block.timestamp >= proposal.endTime + EXECUTION_DELAY, "Execution delay not ended");
        require(proposalTotalVotes[proposalId] >= MINIMUM_QUORUM, "Quorum not reached");
        require(proposal.forVotes > proposal.againstVotes, "Proposal not passed");
        
        proposal.executed = true;
        
        (bool success, ) = proposalTarget[proposalId].call(proposalCallData[proposalId]);
        require(success, "Proposal execution failed");
        
        emit ProposalExecuted(proposalId);
    }
    
    function cancelProposal(uint256 proposalId) external nonReentrant validProposal(proposalId) {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Already executed");
        require(!proposal.canceled, "Already canceled");
        require(msg.sender == proposal.proposer || msg.sender == owner(), "Not authorized");
        
        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }
    
    // Internal functions
    function calculateRewards(address user) public view returns (uint256) {
        Stake storage userStake = stakes[user];
        if (!userStake.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - userStake.startTime;
        uint256 rewards = (userStake.amount * REWARD_RATE * timeElapsed) / (365 days * 100);
        
        return rewards;
    }
    
    function _calculateVotingPower(address account) internal view returns (uint256) {
        Stake storage userStake = stakes[account];
        if (!userStake.isActive) return 0;
        
        // Quadratic voting
        return uint256(sqrt(userStake.amount));
    }
    
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
    
    // Emergency functions
    function emergencyPause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token address");
        IERC20 tokenToWithdraw = IERC20(tokenAddress);
        uint256 balance = tokenToWithdraw.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        tokenToWithdraw.safeTransfer(owner(), balance);
    }

    // Advanced staking features
    struct StakingTier {
        uint256 minStake;
        uint256 maxStake;
        uint256 rewardMultiplier;
        uint256 lockPeriod;
        uint256 earlyUnstakePenalty;
        bool isActive;
    }

    struct StakingPool {
        uint256 id;
        address token;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 tierCount;
        bool isActive;
        mapping(uint256 => StakingTier) tiers;
        mapping(address => uint256) userStakes;
        mapping(address => uint256) userRewards;
        mapping(address => uint256) userTier;
        mapping(address => uint256) userLockEnd;
    }

    struct Delegation {
        address delegate;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    // Staking pool mappings
    mapping(uint256 => StakingPool) public stakingPools;
    Counters.Counter private stakingPoolCounter;
    
    // User delegations
    mapping(address => mapping(address => Delegation)) public delegations;
    mapping(address => uint256) public totalDelegated;
    mapping(address => uint256) public totalDelegatedTo;
    
    // Events for advanced staking
    event StakingPoolCreated(uint256 indexed poolId, address token);
    event StakingTierAdded(uint256 indexed poolId, uint256 indexed tierId, uint256 minStake, uint256 maxStake);
    event StakingTierUpdated(uint256 indexed poolId, uint256 indexed tierId);
    event StakingTierDeactivated(uint256 indexed poolId, uint256 indexed tierId);
    event Delegated(address indexed from, address indexed to, uint256 amount);
    event DelegationRevoked(address indexed from, address indexed to);
    event EarlyUnstake(address indexed user, uint256 amount, uint256 penalty);
    
    // Advanced staking functions
    function createStakingPool(address _token, uint256 _rewardRate) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_rewardRate <= 100, "Invalid reward rate");
        
        stakingPoolCounter.increment();
        uint256 poolId = stakingPoolCounter.current();
        
        StakingPool storage pool = stakingPools[poolId];
        pool.id = poolId;
        pool.token = _token;
        pool.rewardRate = _rewardRate;
        pool.lastUpdateTime = block.timestamp;
        pool.isActive = true;
        
        emit StakingPoolCreated(poolId, _token);
    }
    
    function addStakingTier(
        uint256 poolId,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 lockPeriod,
        uint256 earlyUnstakePenalty
    ) external onlyOwner {
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        require(minStake < maxStake, "Invalid stake range");
        require(rewardMultiplier >= 100, "Invalid multiplier");
        require(lockPeriod >= MIN_LOCK_PERIOD, "Lock period too short");
        require(earlyUnstakePenalty <= 100, "Invalid penalty");
        
        uint256 tierId = pool.tierCount++;
        pool.tiers[tierId] = StakingTier({
            minStake: minStake,
            maxStake: maxStake,
            rewardMultiplier: rewardMultiplier,
            lockPeriod: lockPeriod,
            earlyUnstakePenalty: earlyUnstakePenalty,
            isActive: true
        });
        
        emit StakingTierAdded(poolId, tierId, minStake, maxStake);
    }
    
    function updateStakingTier(
        uint256 poolId,
        uint256 tierId,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 lockPeriod,
        uint256 earlyUnstakePenalty
    ) external onlyOwner {
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        require(tierId < pool.tierCount, "Invalid tier");
        
        StakingTier storage tier = pool.tiers[tierId];
        require(tier.isActive, "Tier not active");
        require(minStake < maxStake, "Invalid stake range");
        require(rewardMultiplier >= 100, "Invalid multiplier");
        require(lockPeriod >= MIN_LOCK_PERIOD, "Lock period too short");
        require(earlyUnstakePenalty <= 100, "Invalid penalty");
        
        tier.minStake = minStake;
        tier.maxStake = maxStake;
        tier.rewardMultiplier = rewardMultiplier;
        tier.lockPeriod = lockPeriod;
        tier.earlyUnstakePenalty = earlyUnstakePenalty;
        
        emit StakingTierUpdated(poolId, tierId);
    }
    
    function deactivateStakingTier(uint256 poolId, uint256 tierId) external onlyOwner {
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        require(tierId < pool.tierCount, "Invalid tier");
        
        StakingTier storage tier = pool.tiers[tierId];
        require(tier.isActive, "Tier not active");
        
        tier.isActive = false;
        emit StakingTierDeactivated(poolId, tierId);
    }
    
    function delegate(address to, uint256 amount) external nonReentrant {
        require(to != address(0) && to != msg.sender, "Invalid delegate");
        require(amount > 0, "Amount must be positive");
        
        Stake storage userStake = stakes[msg.sender];
        require(userStake.isActive, "Not staking");
        require(userStake.amount >= amount, "Insufficient stake");
        
        Delegation storage delegation = delegations[msg.sender][to];
        require(!delegation.isActive, "Already delegating");
        
        delegation.delegate = to;
        delegation.amount = amount;
        delegation.startTime = block.timestamp;
        delegation.endTime = block.timestamp + userStake.lockPeriod;
        delegation.isActive = true;
        
        totalDelegated[msg.sender] += amount;
        totalDelegatedTo[to] += amount;
        
        emit Delegated(msg.sender, to, amount);
    }
    
    function revokeDelegation(address to) external nonReentrant {
        Delegation storage delegation = delegations[msg.sender][to];
        require(delegation.isActive, "No active delegation");
        
        uint256 amount = delegation.amount;
        delegation.isActive = false;
        
        totalDelegated[msg.sender] -= amount;
        totalDelegatedTo[to] -= amount;
        
        emit DelegationRevoked(msg.sender, to);
    }
    
    function earlyUnstake(uint256 poolId) external nonReentrant {
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        
        uint256 userStake = pool.userStakes[msg.sender];
        require(userStake > 0, "No stake to unstake");
        
        uint256 userTierId = pool.userTier[msg.sender];
        StakingTier storage tier = pool.tiers[userTierId];
        require(tier.isActive, "Tier not active");
        
        uint256 penalty = (userStake * tier.earlyUnstakePenalty) / 100;
        uint256 amount = userStake - penalty;
        
        pool.totalStaked -= userStake;
        pool.userStakes[msg.sender] = 0;
        pool.userTier[msg.sender] = 0;
        pool.userLockEnd[msg.sender] = 0;
        
        IERC20(pool.token).safeTransfer(msg.sender, amount);
        emit EarlyUnstake(msg.sender, amount, penalty);
    }
    
    // View functions for advanced staking
    function getStakingPool(uint256 poolId) external view returns (
        uint256 id,
        address tokenAddress,
        uint256 totalStaked,
        uint256 rewardRate,
        uint256 lastUpdateTime,
        uint256 tierCount,
        bool isActive
    ) {
        StakingPool storage pool = stakingPools[poolId];
        return (
            pool.id,
            pool.token,
            pool.totalStaked,
            pool.rewardRate,
            pool.lastUpdateTime,
            pool.tierCount,
            pool.isActive
        );
    }
    
    function getStakingTier(uint256 poolId, uint256 tierId) external view returns (
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 lockPeriod,
        uint256 earlyUnstakePenalty,
        bool isActive
    ) {
        StakingPool storage pool = stakingPools[poolId];
        StakingTier storage tier = pool.tiers[tierId];
        return (
            tier.minStake,
            tier.maxStake,
            tier.rewardMultiplier,
            tier.lockPeriod,
            tier.earlyUnstakePenalty,
            tier.isActive
        );
    }
    
    function getDelegation(address from, address to) external view returns (
        address delegateAddress,
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        Delegation storage delegation = delegations[from][to];
        return (
            delegation.delegate,
            delegation.amount,
            delegation.startTime,
            delegation.endTime,
            delegation.isActive
        );
    }

    // Advanced liquidity pool features
    struct ConcentratedLiquidity {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        bool isActive;
    }

    struct FeeTier {
        uint24 fee;
        int24 tickSpacing;
        bool isActive;
    }

    // Concentrated liquidity mappings
    mapping(uint256 => mapping(address => ConcentratedLiquidity)) public concentratedLiquidity;
    mapping(uint256 => mapping(uint256 => FeeTier)) public feeTiers;
    mapping(uint256 => uint256) public poolFeeTierCount;
    
    // Events for advanced liquidity
    event ConcentratedLiquidityAdded(
        uint256 indexed poolId,
        address indexed owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    );
    event ConcentratedLiquidityRemoved(
        uint256 indexed poolId,
        address indexed owner,
        uint128 liquidity
    );
    event FeeTierCreated(uint256 indexed poolId, uint256 indexed tierId, uint24 fee, int24 tickSpacing);
    event FeeTierUpdated(uint256 indexed poolId, uint256 indexed tierId);
    event FeeTierDeactivated(uint256 indexed poolId, uint256 indexed tierId);
    
    // Advanced liquidity functions
    function addConcentratedLiquidity(
        uint256 poolId,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external nonReentrant validPool(poolId) {
        require(lowerTick < upperTick, "Invalid tick range");
        require(liquidity > 0, "Liquidity must be positive");
        
        ConcentratedLiquidity storage position = concentratedLiquidity[poolId][msg.sender];
        require(!position.isActive, "Position already exists");
        
        position.lowerTick = lowerTick;
        position.upperTick = upperTick;
        position.liquidity = liquidity;
        position.isActive = true;
        
        emit ConcentratedLiquidityAdded(poolId, msg.sender, lowerTick, upperTick, liquidity);
    }
    
    function removeConcentratedLiquidity(
        uint256 poolId,
        uint128 liquidity
    ) external nonReentrant validPool(poolId) {
        ConcentratedLiquidity storage position = concentratedLiquidity[poolId][msg.sender];
        require(position.isActive, "No active position");
        require(liquidity <= position.liquidity, "Insufficient liquidity");
        
        position.liquidity -= liquidity;
        if (position.liquidity == 0) {
            position.isActive = false;
        }
        
        emit ConcentratedLiquidityRemoved(poolId, msg.sender, liquidity);
    }
    
    function createFeeTier(
        uint256 poolId,
        uint24 fee,
        int24 tickSpacing
    ) external onlyOwner validPool(poolId) {
        require(fee <= 10000, "Fee too high"); // Max 1%
        require(tickSpacing > 0, "Invalid tick spacing");
        
        uint256 tierId = poolFeeTierCount[poolId]++;
        feeTiers[poolId][tierId] = FeeTier({
            fee: fee,
            tickSpacing: tickSpacing,
            isActive: true
        });
        
        emit FeeTierCreated(poolId, tierId, fee, tickSpacing);
    }
    
    function updateFeeTier(
        uint256 poolId,
        uint256 tierId,
        uint24 fee,
        int24 tickSpacing
    ) external onlyOwner validPool(poolId) {
        require(tierId < poolFeeTierCount[poolId], "Invalid tier");
        require(fee <= 10000, "Fee too high");
        require(tickSpacing > 0, "Invalid tick spacing");
        
        FeeTier storage tier = feeTiers[poolId][tierId];
        require(tier.isActive, "Tier not active");
        
        tier.fee = fee;
        tier.tickSpacing = tickSpacing;
        
        emit FeeTierUpdated(poolId, tierId);
    }
    
    function deactivateFeeTier(uint256 poolId, uint256 tierId) external onlyOwner validPool(poolId) {
        require(tierId < poolFeeTierCount[poolId], "Invalid tier");
        
        FeeTier storage tier = feeTiers[poolId][tierId];
        require(tier.isActive, "Tier not active");
        
        tier.isActive = false;
        emit FeeTierDeactivated(poolId, tierId);
    }
    
    // View functions for advanced liquidity
    function getConcentratedLiquidity(
        uint256 poolId,
        address owner
    ) external view returns (
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1,
        bool isActive
    ) {
        ConcentratedLiquidity storage position = concentratedLiquidity[poolId][owner];
        return (
            position.lowerTick,
            position.upperTick,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1,
            position.isActive
        );
    }
    
    function getFeeTier(
        uint256 poolId,
        uint256 tierId
    ) external view returns (
        uint24 fee,
        int24 tickSpacing,
        bool isActive
    ) {
        FeeTier storage tier = feeTiers[poolId][tierId];
        return (
            tier.fee,
            tier.tickSpacing,
            tier.isActive
        );
    }

    // Advanced governance features
    struct Timelock {
        uint256 delay;
        uint256 gracePeriod;
        uint256 minimumDelay;
        uint256 maximumDelay;
        uint256 proposalThreshold;
        uint256 quorumNumerator;
        uint256 quorumDenominator;
        uint256 votingPeriod;
        uint256 votingDelay;
        uint256 proposalCount;
    }

    struct ProposalCategory {
        string name;
        string description;
        uint256 proposalThreshold;
        uint256 votingPeriod;
        uint256 quorumNumerator;
        uint256 quorumDenominator;
        bool isActive;
    }

    // Advanced governance state
    Timelock public timelock;
    mapping(uint256 => ProposalCategory) public proposalCategories;
    mapping(uint256 => uint256) public proposalTimestamps;
    Counters.Counter private categoryCounter;
    
    // Events for advanced governance
    event TimelockInitialized(
        uint256 delay,
        uint256 gracePeriod,
        uint256 minimumDelay,
        uint256 maximumDelay
    );
    event TimelockUpdated(
        uint256 oldDelay,
        uint256 newDelay,
        uint256 oldGracePeriod,
        uint256 newGracePeriod
    );
    event ProposalCategoryCreated(
        uint256 indexed categoryId,
        string name,
        string description
    );
    event ProposalCategoryUpdated(uint256 indexed categoryId);
    event ProposalCategoryDeactivated(uint256 indexed categoryId);
    
    // Advanced governance functions
    function initializeTimelock(
        uint256 _delay,
        uint256 _gracePeriod,
        uint256 _minimumDelay,
        uint256 _maximumDelay
    ) external onlyOwner {
        require(_delay >= _minimumDelay, "Delay below minimum");
        require(_delay <= _maximumDelay, "Delay above maximum");
        require(_gracePeriod > 0, "Invalid grace period");
        
        timelock = Timelock({
            delay: _delay,
            gracePeriod: _gracePeriod,
            minimumDelay: _minimumDelay,
            maximumDelay: _maximumDelay,
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorumNumerator: 1,
            quorumDenominator: 10,
            votingPeriod: VOTING_PERIOD,
            votingDelay: 1 days,
            proposalCount: 0
        });
        
        emit TimelockInitialized(_delay, _gracePeriod, _minimumDelay, _maximumDelay);
    }
    
    function updateTimelock(
        uint256 _delay,
        uint256 _gracePeriod
    ) external onlyOwner {
        require(_delay >= timelock.minimumDelay, "Delay below minimum");
        require(_delay <= timelock.maximumDelay, "Delay above maximum");
        require(_gracePeriod > 0, "Invalid grace period");
        
        uint256 oldDelay = timelock.delay;
        uint256 oldGracePeriod = timelock.gracePeriod;
        
        timelock.delay = _delay;
        timelock.gracePeriod = _gracePeriod;
        
        emit TimelockUpdated(oldDelay, _delay, oldGracePeriod, _gracePeriod);
    }
    
    function createProposalCategory(
        string memory name,
        string memory description,
        uint256 proposalThreshold,
        uint256 votingPeriod,
        uint256 quorumNumerator,
        uint256 quorumDenominator
    ) external onlyOwner {
        require(bytes(name).length > 0, "Empty name");
        require(proposalThreshold > 0, "Invalid threshold");
        require(votingPeriod > 0, "Invalid voting period");
        require(quorumNumerator > 0, "Invalid quorum numerator");
        require(quorumDenominator > 0, "Invalid quorum denominator");
        require(quorumNumerator <= quorumDenominator, "Invalid quorum ratio");
        
        categoryCounter.increment();
        uint256 categoryId = categoryCounter.current();
        
        proposalCategories[categoryId] = ProposalCategory({
            name: name,
            description: description,
            proposalThreshold: proposalThreshold,
            votingPeriod: votingPeriod,
            quorumNumerator: quorumNumerator,
            quorumDenominator: quorumDenominator,
            isActive: true
        });
        
        emit ProposalCategoryCreated(categoryId, name, description);
    }
    
    function updateProposalCategory(
        uint256 categoryId,
        string memory name,
        string memory description,
        uint256 proposalThreshold,
        uint256 votingPeriod,
        uint256 quorumNumerator,
        uint256 quorumDenominator
    ) external onlyOwner {
        require(categoryId <= categoryCounter.current(), "Invalid category");
        require(bytes(name).length > 0, "Empty name");
        require(proposalThreshold > 0, "Invalid threshold");
        require(votingPeriod > 0, "Invalid voting period");
        require(quorumNumerator > 0, "Invalid quorum numerator");
        require(quorumDenominator > 0, "Invalid quorum denominator");
        require(quorumNumerator <= quorumDenominator, "Invalid quorum ratio");
        
        ProposalCategory storage category = proposalCategories[categoryId];
        require(category.isActive, "Category not active");
        
        category.name = name;
        category.description = description;
        category.proposalThreshold = proposalThreshold;
        category.votingPeriod = votingPeriod;
        category.quorumNumerator = quorumNumerator;
        category.quorumDenominator = quorumDenominator;
        
        emit ProposalCategoryUpdated(categoryId);
    }
    
    function deactivateProposalCategory(uint256 categoryId) external onlyOwner {
        require(categoryId <= categoryCounter.current(), "Invalid category");
        
        ProposalCategory storage category = proposalCategories[categoryId];
        require(category.isActive, "Category not active");
        
        category.isActive = false;
        emit ProposalCategoryDeactivated(categoryId);
    }
    
    // View functions for advanced governance
    function getTimelock() external view returns (
        uint256 delay,
        uint256 gracePeriod,
        uint256 minimumDelay,
        uint256 maximumDelay,
        uint256 proposalThreshold,
        uint256 quorumNumerator,
        uint256 quorumDenominator,
        uint256 votingPeriod,
        uint256 votingDelay,
        uint256 proposalCount
    ) {
        return (
            timelock.delay,
            timelock.gracePeriod,
            timelock.minimumDelay,
            timelock.maximumDelay,
            timelock.proposalThreshold,
            timelock.quorumNumerator,
            timelock.quorumDenominator,
            timelock.votingPeriod,
            timelock.votingDelay,
            timelock.proposalCount
        );
    }
    
    function getProposalCategory(uint256 categoryId) external view returns (
        string memory name,
        string memory description,
        uint256 proposalThreshold,
        uint256 votingPeriod,
        uint256 quorumNumerator,
        uint256 quorumDenominator,
        bool isActive
    ) {
        ProposalCategory storage category = proposalCategories[categoryId];
        return (
            category.name,
            category.description,
            category.proposalThreshold,
            category.votingPeriod,
            category.quorumNumerator,
            category.quorumDenominator,
            category.isActive
        );
    }

    // Reward distribution and fee management features
    struct RewardDistribution {
        uint256 totalRewards;
        uint256 lastDistributionTime;
        uint256 distributionPeriod;
        uint256 rewardRate;
        uint256 minimumStake;
        uint256 maximumStake;
        bool isActive;
    }

    struct FeeConfiguration {
        uint256 protocolFee;
        uint256 stakingFee;
        uint256 liquidityFee;
        uint256 governanceFee;
        address feeCollector;
    }

    // Reward distribution mappings
    mapping(uint256 => RewardDistribution) public rewardDistributions;
    Counters.Counter private distributionCounter;
    
    // Fee configuration
    FeeConfiguration public feeConfig;
    
    // Events for reward distribution and fee management
    event RewardDistributionCreated(
        uint256 indexed distributionId,
        uint256 distributionPeriod,
        uint256 rewardRate
    );
    event RewardDistributionUpdated(
        uint256 indexed distributionId,
        uint256 distributionPeriod,
        uint256 rewardRate
    );
    event RewardDistributionDeactivated(uint256 indexed distributionId);
    event RewardsDistributed(uint256 indexed distributionId, uint256 amount);
    event FeeConfigurationUpdated(
        uint256 protocolFee,
        uint256 stakingFee,
        uint256 liquidityFee,
        uint256 governanceFee
    );
    
    // Reward distribution and fee management functions
    function createRewardDistribution(
        uint256 distributionPeriod,
        uint256 rewardRate,
        uint256 minimumStake,
        uint256 maximumStake
    ) external onlyOwner {
        require(distributionPeriod > 0, "Invalid period");
        require(rewardRate > 0, "Invalid rate");
        require(minimumStake < maximumStake, "Invalid stake range");
        
        distributionCounter.increment();
        uint256 distributionId = distributionCounter.current();
        
        rewardDistributions[distributionId] = RewardDistribution({
            totalRewards: 0,
            lastDistributionTime: block.timestamp,
            distributionPeriod: distributionPeriod,
            rewardRate: rewardRate,
            minimumStake: minimumStake,
            maximumStake: maximumStake,
            isActive: true
        });
        
        emit RewardDistributionCreated(distributionId, distributionPeriod, rewardRate);
    }
    
    function updateRewardDistribution(
        uint256 distributionId,
        uint256 distributionPeriod,
        uint256 rewardRate
    ) external onlyOwner {
        require(distributionId <= distributionCounter.current(), "Invalid distribution");
        require(distributionPeriod > 0, "Invalid period");
        require(rewardRate > 0, "Invalid rate");
        
        RewardDistribution storage distribution = rewardDistributions[distributionId];
        require(distribution.isActive, "Distribution not active");
        
        distribution.distributionPeriod = distributionPeriod;
        distribution.rewardRate = rewardRate;
        
        emit RewardDistributionUpdated(distributionId, distributionPeriod, rewardRate);
    }
    
    function deactivateRewardDistribution(uint256 distributionId) external onlyOwner {
        require(distributionId <= distributionCounter.current(), "Invalid distribution");
        
        RewardDistribution storage distribution = rewardDistributions[distributionId];
        require(distribution.isActive, "Distribution not active");
        
        distribution.isActive = false;
        emit RewardDistributionDeactivated(distributionId);
    }
    
    function distributeRewards(uint256 distributionId) external nonReentrant {
        require(distributionId <= distributionCounter.current(), "Invalid distribution");
        
        RewardDistribution storage distribution = rewardDistributions[distributionId];
        require(distribution.isActive, "Distribution not active");
        require(
            block.timestamp >= distribution.lastDistributionTime + distribution.distributionPeriod,
            "Too early to distribute"
        );
        
        uint256 totalEligibleStake = 0;
        address[] memory stakers = new address[](1000); // Assuming max 1000 stakers
        uint256 stakerCount = 0;
        
        // Calculate total eligible stake and collect stakers
        for (uint256 i = 0; i < 1000; i++) {
            address staker = address(uint160(i + 1)); // Simplified staker address generation
            Stake storage userStake = stakes[staker];
            if (userStake.isActive && 
                userStake.amount >= distribution.minimumStake && 
                userStake.amount <= distribution.maximumStake) {
                totalEligibleStake += userStake.amount;
                stakers[stakerCount++] = staker;
            }
        }
        
        require(totalEligibleStake > 0, "No eligible stakers");
        
        // Calculate and distribute rewards
        uint256 rewards = (totalEligibleStake * distribution.rewardRate * distribution.distributionPeriod) / (365 days * 100);
        require(rewards > 0, "No rewards to distribute");
        
        for (uint256 i = 0; i < stakerCount; i++) {
            address staker = stakers[i];
            Stake storage userStake = stakes[staker];
            uint256 userReward = (userStake.amount * rewards) / totalEligibleStake;
            
            if (userReward > 0) {
                token.safeTransfer(staker, userReward);
            }
        }
        
        distribution.lastDistributionTime = block.timestamp;
        distribution.totalRewards += rewards;
        
        emit RewardsDistributed(distributionId, rewards);
    }
    
    function updateFeeConfiguration(
        uint256 protocolFee,
        uint256 stakingFee,
        uint256 liquidityFee,
        uint256 governanceFee
    ) external onlyOwner {
        require(protocolFee <= 1000, "Protocol fee too high"); // Max 10%
        require(stakingFee <= 1000, "Staking fee too high");
        require(liquidityFee <= 1000, "Liquidity fee too high");
        require(governanceFee <= 1000, "Governance fee too high");
        
        feeConfig.protocolFee = protocolFee;
        feeConfig.stakingFee = stakingFee;
        feeConfig.liquidityFee = liquidityFee;
        feeConfig.governanceFee = governanceFee;
        
        emit FeeConfigurationUpdated(protocolFee, stakingFee, liquidityFee, governanceFee);
    }
    
    function updateFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "Invalid collector");
        
        address oldCollector = feeConfig.feeCollector;
        feeConfig.feeCollector = newCollector;
        
        emit FeeCollectorUpdated(oldCollector, newCollector);
    }
    
    // View functions for reward distribution and fee management
    function getRewardDistribution(uint256 distributionId) external view returns (
        uint256 totalRewards,
        uint256 lastDistributionTime,
        uint256 distributionPeriod,
        uint256 rewardRate,
        uint256 minimumStake,
        uint256 maximumStake,
        bool isActive
    ) {
        RewardDistribution storage distribution = rewardDistributions[distributionId];
        return (
            distribution.totalRewards,
            distribution.lastDistributionTime,
            distribution.distributionPeriod,
            distribution.rewardRate,
            distribution.minimumStake,
            distribution.maximumStake,
            distribution.isActive
        );
    }
    
    function getFeeConfiguration() external view returns (
        uint256 protocolFee,
        uint256 stakingFee,
        uint256 liquidityFee,
        uint256 governanceFee,
        address feeCollector
    ) {
        return (
            feeConfig.protocolFee,
            feeConfig.stakingFee,
            feeConfig.liquidityFee,
            feeConfig.governanceFee,
            feeConfig.feeCollector
        );
    }

    // Advanced swap and price oracle features
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 deadline;
        uint256 fee;
        bool isExactInput;
    }

    struct PriceOracle {
        address token;
        uint256 price;
        uint256 lastUpdateTime;
        uint256 decimals;
        bool isActive;
    }

    // Swap and price oracle mappings
    mapping(address => PriceOracle) public priceOracles;
    mapping(address => mapping(address => uint256)) public reserves;
    mapping(address => mapping(address => uint256)) public lastPrices;
    
    // Events for advanced swap and price oracle
    event PriceOracleAdded(address indexed token, uint256 decimals);
    event PriceOracleUpdated(address indexed token, uint256 price);
    event PriceOracleDeactivated(address indexed token);
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    event ReservesUpdated(
        address indexed token0,
        address indexed token1,
        uint256 reserve0,
        uint256 reserve1
    );
    
    // Advanced swap and price oracle functions
    function addPriceOracle(
        address tokenAddress,
        uint256 decimals
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(decimals <= 18, "Invalid decimals");
        
        priceOracles[tokenAddress] = PriceOracle({
            token: tokenAddress,
            price: 0,
            lastUpdateTime: block.timestamp,
            decimals: decimals,
            isActive: true
        });
        
        emit PriceOracleAdded(tokenAddress, decimals);
    }
    
    function updatePriceOracle(
        address tokenAddress,
        uint256 price
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        
        PriceOracle storage oracle = priceOracles[tokenAddress];
        require(oracle.isActive, "Oracle not active");
        
        oracle.price = price;
        oracle.lastUpdateTime = block.timestamp;
        
        emit PriceOracleUpdated(tokenAddress, price);
    }
    
    function deactivatePriceOracle(
        address tokenAddress
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        
        PriceOracle storage oracle = priceOracles[tokenAddress];
        require(oracle.isActive, "Oracle not active");
        
        oracle.isActive = false;
        emit PriceOracleDeactivated(tokenAddress);
    }
    
    function swapExactTokensForTokens(
        address tokenInAddress,  // Changed from tokenIn to tokenInAddress
        address tokenOutAddress,  // Changed from tokenOut to tokenOutAddress
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        require(block.timestamp <= deadline, "Deadline expired");
        require(amountIn > 0, "Amount must be positive");
        require(amountOutMin > 0, "Min output must be positive");
        
        SwapParams memory params = SwapParams({
            tokenIn: tokenInAddress,
            tokenOut: tokenOutAddress,
            amountIn: amountIn,
            amountOutMin: amountOutMin,
            deadline: deadline,
            fee: feeConfig.liquidityFee,
            isExactInput: true
        });
        
        uint256 amountOut = _executeSwap(params);
        require(amountOut >= amountOutMin, "Insufficient output");
        
        emit SwapExecuted(tokenInAddress, tokenOutAddress, amountIn, amountOut);
    }
    
    function swapTokensForExactTokens(
        address tokenInAddress,  // Changed from tokenIn to tokenInAddress
        address tokenOutAddress,  // Changed from tokenOut to tokenOutAddress
        uint256 amountOut,
        uint256 amountInMax,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        require(block.timestamp <= deadline, "Deadline expired");
        require(amountOut > 0, "Amount must be positive");
        require(amountInMax > 0, "Max input must be positive");
        
        SwapParams memory params = SwapParams({
            tokenIn: tokenInAddress,
            tokenOut: tokenOutAddress,
            amountIn: amountInMax,
            amountOutMin: amountOut,
            deadline: deadline,
            fee: feeConfig.liquidityFee,
            isExactInput: false
        });
        
        uint256 amountIn = _executeSwap(params);
        require(amountIn <= amountInMax, "Excessive input");
        
        emit SwapExecuted(tokenInAddress, tokenOutAddress, amountIn, amountOut);
    }
    
    function _executeSwap(
        SwapParams memory params
    ) internal returns (uint256) {  // Remove fee from return values
        require(params.tokenIn != params.tokenOut, "Identical tokens");
        
        uint256 reserveIn = reserves[params.tokenIn][params.tokenOut];
        uint256 reserveOut = reserves[params.tokenOut][params.tokenIn];
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        uint256 amountInWithFee = params.isExactInput ? 
            params.amountIn * (10000 - params.fee) / 10000 :
            params.amountIn;
        
        uint256 amountOut = params.isExactInput ?
            (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee) :
            (params.amountOutMin * reserveIn) / (reserveOut - params.amountOutMin);
        
        uint256 fee = params.isExactInput ?
            params.amountIn - amountInWithFee :
            (amountOut * params.fee) / 10000;
        
        require(amountOut > 0, "Insufficient output");
        
        reserves[params.tokenIn][params.tokenOut] += params.amountIn;
        reserves[params.tokenOut][params.tokenIn] -= amountOut;
        
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).safeTransfer(msg.sender, amountOut);
        
        if (fee > 0) {
            IERC20(params.tokenIn).safeTransfer(feeConfig.feeCollector, fee);
        }
        
        emit ReservesUpdated(
            params.tokenIn,
            params.tokenOut,
            reserves[params.tokenIn][params.tokenOut],
            reserves[params.tokenOut][params.tokenIn]
        );
        
        return params.isExactInput ? amountOut : params.amountIn;
    }
    
    // View functions for advanced swap and price oracle
    function getPriceOracle(address tokenAddress) public view returns (
        uint256 price,
        uint256 lastUpdateTime,
        uint256 decimals,
        bool isActive
    ) {
        PriceOracle storage oracle = priceOracles[tokenAddress];
        return (
            oracle.price,
            oracle.lastUpdateTime,
            oracle.decimals,
            oracle.isActive
        );
    }
    
    function getReserves(
        address token0,
        address token1
    ) external view returns (
        uint256 reserve0,
        uint256 reserve1
    ) {
        return (
            reserves[token0][token1],
            reserves[token1][token0]
        );
    }
    
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256) {
        require(tokenIn != tokenOut, "Identical tokens");
        
        uint256 reserveIn = reserves[tokenIn][tokenOut];
        uint256 reserveOut = reserves[tokenOut][tokenIn];
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        uint256 amountInWithFee = amountIn * (10000 - feeConfig.liquidityFee) / 10000;
        return (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);
    }
    
    function getAmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256) {
        require(tokenIn != tokenOut, "Identical tokens");
        
        uint256 reserveIn = reserves[tokenIn][tokenOut];
        uint256 reserveOut = reserves[tokenOut][tokenIn];
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        return (amountOut * reserveIn) / (reserveOut - amountOut);
    }

    // Advanced yield farming features
    struct YieldFarm {
        uint256 id;
        address token;
        address rewardToken;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 totalStaked;
        uint256 totalRewards;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        mapping(address => uint256) userStakes;
        mapping(address => uint256) userRewards;
        mapping(address => uint256) userLastUpdateTime;
    }

    struct YieldFarmConfig {
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        uint256 lockPeriod;
        uint256 earlyUnstakePenalty;
        uint256 rewardMultiplier;
        bool isActive;
    }

    // Yield farming mappings
    mapping(uint256 => YieldFarm) public yieldFarms;
    mapping(uint256 => YieldFarmConfig) public yieldFarmConfigs;
    Counters.Counter private yieldFarmCounter;
    
    // Flash loan features
    struct FlashLoan {
        address token;
        uint256 amount;
        uint256 fee;
        uint256 deadline;
        bool isActive;
    }

    mapping(address => FlashLoan) public flashLoans;
    uint256 public constant FLASH_LOAN_FEE = 5; // 0.05%
    
    // Events for yield farming and flash loans
    event YieldFarmCreated(
        uint256 indexed farmId,
        address token,
        address rewardToken,
        uint256 rewardRate
    );
    event YieldFarmConfigUpdated(
        uint256 indexed farmId,
        uint256 minStakeAmount,
        uint256 maxStakeAmount
    );
    event YieldFarmStaked(
        uint256 indexed farmId,
        address indexed user,
        uint256 amount
    );
    event YieldFarmUnstaked(
        uint256 indexed farmId,
        address indexed user,
        uint256 amount
    );
    event YieldFarmRewardsClaimed(
        uint256 indexed farmId,
        address indexed user,
        uint256 amount
    );
    event FlashLoanBorrowed(
        address indexed token,
        address indexed borrower,
        uint256 amount,
        uint256 fee
    );
    event FlashLoanRepaid(
        address indexed token,
        address indexed borrower,
        uint256 amount,
        uint256 fee
    );
    
    // Yield farming functions
    function createYieldFarm(
        address tokenAddress,
        address rewardTokenAddress,
        uint256 _rewardRate,
        uint256 _startTime,
        uint256 _endTime
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(rewardTokenAddress != address(0), "Invalid reward token");
        require(_rewardRate > 0, "Invalid reward rate");
        require(_startTime > block.timestamp, "Invalid start time");
        require(_endTime > _startTime, "Invalid end time");
        
        yieldFarmCounter.increment();
        uint256 farmId = yieldFarmCounter.current();
        
        YieldFarm storage farm = yieldFarms[farmId];
        farm.id = farmId;
        farm.token = tokenAddress;
        farm.rewardToken = rewardTokenAddress;
        farm.rewardRate = _rewardRate;
        farm.lastUpdateTime = block.timestamp;
        farm.startTime = _startTime;
        farm.endTime = _endTime;
        farm.isActive = true;
        
        emit YieldFarmCreated(farmId, tokenAddress, rewardTokenAddress, _rewardRate);
    }
    
    function updateYieldFarmConfig(
        uint256 farmId,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 lockPeriod,
        uint256 earlyUnstakePenalty,
        uint256 rewardMultiplier
    ) external onlyOwner {
        require(farmId <= yieldFarmCounter.current(), "Invalid farm");
        require(minStakeAmount < maxStakeAmount, "Invalid stake range");
        require(lockPeriod >= MIN_LOCK_PERIOD, "Lock period too short");
        require(earlyUnstakePenalty <= 100, "Invalid penalty");
        require(rewardMultiplier >= 100, "Invalid multiplier");
        
        YieldFarmConfig storage config = yieldFarmConfigs[farmId];
        config.minStakeAmount = minStakeAmount;
        config.maxStakeAmount = maxStakeAmount;
        config.lockPeriod = lockPeriod;
        config.earlyUnstakePenalty = earlyUnstakePenalty;
        config.rewardMultiplier = rewardMultiplier;
        config.isActive = true;
        
        emit YieldFarmConfigUpdated(farmId, minStakeAmount, maxStakeAmount);
    }
    
    function stakeInYieldFarm(
        uint256 farmId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(farmId <= yieldFarmCounter.current(), "Invalid farm");
        
        YieldFarm storage farm = yieldFarms[farmId];
        require(farm.isActive, "Farm not active");
        require(block.timestamp >= farm.startTime, "Farm not started");
        require(block.timestamp <= farm.endTime, "Farm ended");
        
        YieldFarmConfig storage config = yieldFarmConfigs[farmId];
        require(config.isActive, "Config not active");
        require(amount >= config.minStakeAmount, "Amount below minimum");
        require(amount <= config.maxStakeAmount, "Amount above maximum");
        
        _updateYieldFarmRewards(farmId, msg.sender);
        
        IERC20(farm.token).safeTransferFrom(msg.sender, address(this), amount);
        
        farm.totalStaked += amount;
        farm.userStakes[msg.sender] += amount;
        farm.userLastUpdateTime[msg.sender] = block.timestamp;
        
        emit YieldFarmStaked(farmId, msg.sender, amount);
    }
    
    function unstakeFromYieldFarm(
        uint256 farmId,
        uint256 amount
    ) external nonReentrant {
        require(farmId <= yieldFarmCounter.current(), "Invalid farm");
        
        YieldFarm storage farm = yieldFarms[farmId];
        require(farm.isActive, "Farm not active");
        
        YieldFarmConfig storage config = yieldFarmConfigs[farmId];
        require(config.isActive, "Config not active");
        
        _updateYieldFarmRewards(farmId, msg.sender);
        
        require(farm.userStakes[msg.sender] >= amount, "Insufficient stake");
        
        uint256 penalty = 0;
        if (block.timestamp < farm.userLastUpdateTime[msg.sender] + config.lockPeriod) {
            penalty = (amount * config.earlyUnstakePenalty) / 100;
            amount -= penalty;
        }
        
        farm.totalStaked -= amount;
        farm.userStakes[msg.sender] -= amount;
        
        IERC20(farm.token).safeTransfer(msg.sender, amount);
        if (penalty > 0) {
            IERC20(farm.token).safeTransfer(feeConfig.feeCollector, penalty);
        }
        
        emit YieldFarmUnstaked(farmId, msg.sender, amount);
    }
    
    function claimYieldFarmRewards(uint256 farmId) external nonReentrant {
        require(farmId <= yieldFarmCounter.current(), "Invalid farm");
        
        YieldFarm storage farm = yieldFarms[farmId];
        require(farm.isActive, "Farm not active");
        
        _updateYieldFarmRewards(farmId, msg.sender);
        
        uint256 rewards = farm.userRewards[msg.sender];
        require(rewards > 0, "No rewards to claim");
        
        farm.userRewards[msg.sender] = 0;
        farm.totalRewards += rewards;
        
        IERC20(farm.rewardToken).safeTransfer(msg.sender, rewards);
        emit YieldFarmRewardsClaimed(farmId, msg.sender, rewards);
    }
    
    function _updateYieldFarmRewards(uint256 farmId, address user) internal {
        YieldFarm storage farm = yieldFarms[farmId];
        if (!farm.isActive || farm.userStakes[user] == 0) return;
        
        uint256 timeElapsed = block.timestamp - farm.userLastUpdateTime[user];
        uint256 rewards = (farm.userStakes[user] * farm.rewardRate * timeElapsed) / (365 days * 100);
        
        farm.userRewards[user] += rewards;
        farm.userLastUpdateTime[user] = block.timestamp;
    }
    
    // Flash loan functions
    function borrowFlashLoan(
        address tokenAddress,
        uint256 amount,
        uint256 deadline
    ) external nonReentrant whenNotPaused {
        require(tokenAddress != address(0), "Invalid token");
        require(amount > 0, "Amount must be positive");
        require(block.timestamp <= deadline, "Deadline expired");
        
        uint256 fee = (amount * FLASH_LOAN_FEE) / 10000;
        
        require(
            IERC20(tokenAddress).balanceOf(address(this)) >= amount,
            "Insufficient liquidity"
        );
        
        flashLoans[msg.sender] = FlashLoan({
            token: tokenAddress,
            amount: amount,
            fee: fee,
            deadline: deadline,
            isActive: true
        });
        
        IERC20(tokenAddress).safeTransfer(msg.sender, amount);
        emit FlashLoanBorrowed(tokenAddress, msg.sender, amount, fee);
    }
    
    function repayFlashLoan() external nonReentrant {
        FlashLoan storage loan = flashLoans[msg.sender];
        require(loan.isActive, "No active flash loan");
        require(block.timestamp <= loan.deadline, "Flash loan expired");
        
        uint256 repayAmount = loan.amount + loan.fee;
        
        IERC20(loan.token).safeTransferFrom(msg.sender, address(this), repayAmount);
        
        loan.isActive = false;
        emit FlashLoanRepaid(loan.token, msg.sender, loan.amount, loan.fee);
    }
    
    // View functions for yield farming and flash loans
    function getYieldFarm(uint256 farmId) external view returns (
        uint256 id,
        address tokenAddress,  // Changed from token to tokenAddress
        address rewardTokenAddress,  // Changed from rewardToken to rewardTokenAddress
        uint256 rewardRate,
        uint256 lastUpdateTime,
        uint256 totalStaked,
        uint256 totalRewards,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        YieldFarm storage farm = yieldFarms[farmId];
        return (
            farm.id,
            farm.token,
            farm.rewardToken,
            farm.rewardRate,
            farm.lastUpdateTime,
            farm.totalStaked,
            farm.totalRewards,
            farm.startTime,
            farm.endTime,
            farm.isActive
        );
    }
    
    function getYieldFarmConfig(uint256 farmId) external view returns (
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 lockPeriod,
        uint256 earlyUnstakePenalty,
        uint256 rewardMultiplier,
        bool isActive
    ) {
        YieldFarmConfig storage config = yieldFarmConfigs[farmId];
        return (
            config.minStakeAmount,
            config.maxStakeAmount,
            config.lockPeriod,
            config.earlyUnstakePenalty,
            config.rewardMultiplier,
            config.isActive
        );
    }
    
    function getYieldFarmUserInfo(
        uint256 farmId,
        address user
    ) external view returns (
        uint256 userStake,
        uint256 rewards,
        uint256 lastUpdateTime
    ) {
        YieldFarm storage farm = yieldFarms[farmId];
        return (
            farm.userStakes[user],
            farm.userRewards[user],
            farm.userLastUpdateTime[user]
        );
    }
    
    function getFlashLoan(address borrower) external view returns (
        address tokenAddress,
        uint256 amount,
        uint256 fee,
        uint256 deadline,
        bool isActive
    ) {
        FlashLoan storage loan = flashLoans[borrower];
        return (
            loan.token,
            loan.amount,
            loan.fee,
            loan.deadline,
            loan.isActive
        );
    }

    // Advanced risk management features
    struct RiskParameter {
        uint256 maxLeverage;
        uint256 maintenanceMargin;
        uint256 liquidationThreshold;
        uint256 maxPositionSize;
        uint256 minCollateral;
        uint256 maxDrawdown;
        bool isActive;
    }

    struct Position {
        address owner;
        uint256 size;
        uint256 collateral;
        uint256 leverage;
        uint256 entryPrice;
        uint256 liquidationPrice;
        uint256 lastUpdateTime;
        bool isLong;
        bool isActive;
    }

    struct RiskMetrics {
        uint256 totalPositionSize;
        uint256 totalCollateral;
        uint256 maxDrawdown;
        uint256 volatility;
        uint256 sharpeRatio;
        uint256 lastUpdateTime;
    }

    // Risk management mappings
    mapping(address => RiskParameter) public riskParameters;
    mapping(address => mapping(uint256 => Position)) public positions;
    mapping(address => RiskMetrics) public riskMetrics;
    mapping(address => uint256) public positionCount;

    // Events for risk management
    event RiskParameterUpdated(
        address indexed token,
        uint256 maxLeverage,
        uint256 maintenanceMargin,
        uint256 liquidationThreshold
    );
    event PositionOpened(
        address indexed owner,
        address indexed token,
        uint256 indexed positionId,
        uint256 size,
        uint256 collateral,
        uint256 leverage,
        bool isLong
    );
    event PositionClosed(
        address indexed owner,
        address indexed tokenAddress,
        uint256 indexed positionId,
        uint256 pnlAmount
    );
    event PositionLiquidated(
        address indexed owner,
        address indexed token,
        uint256 indexed positionId,
        uint256 deficit
    );
    event RiskMetricsUpdated(
        address indexed token,
        uint256 totalPositionSize,
        uint256 totalCollateral,
        uint256 maxDrawdown
    );

    // Liquidity mining features
    struct LiquidityMiningPool {
        uint256 id;
        address token;
        uint256 rewardRate;
        uint256 totalLiquidity;
        uint256 accumulatedRewardsPerShare;
        uint256 lastUpdateTime;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    struct MinerPosition {
        uint256 liquidity;
        uint256 rewardDebt;
        uint256 lastUpdateTime;
        bool isActive;
    }

    // Liquidity mining mappings
    mapping(uint256 => LiquidityMiningPool) public liquidityMiningPools;
    mapping(uint256 => mapping(address => MinerPosition)) public minerPositions;
    Counters.Counter private liquidityMiningPoolCounter;

    // Events for liquidity mining
    event LiquidityMiningPoolCreated(
        uint256 indexed poolId,
        address token,
        uint256 rewardRate,
        uint256 startTime,
        uint256 endTime
    );
    event LiquidityMiningPositionOpened(
        uint256 indexed poolId,
        address indexed miner,
        uint256 liquidity
    );
    event LiquidityMiningPositionClosed(
        uint256 indexed poolId,
        address indexed miner,
        uint256 liquidity,
        uint256 rewards
    );
    event LiquidityMiningRewardsClaimed(
        uint256 indexed poolId,
        address indexed miner,
        uint256 rewards
    );

    // Risk management functions
    function updateRiskParameters(
        address tokenAddress,
        uint256 maxLeverage,
        uint256 maintenanceMargin,
        uint256 liquidationThreshold,
        uint256 maxPositionSize,
        uint256 minCollateral,
        uint256 maxDrawdown
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(maxLeverage >= 1e18, "Invalid leverage");
        require(maintenanceMargin <= 1e18, "Invalid margin");
        require(liquidationThreshold <= maintenanceMargin, "Invalid threshold");
        require(maxPositionSize > 0, "Invalid position size");
        require(minCollateral > 0, "Invalid collateral");
        require(maxDrawdown <= 1e18, "Invalid drawdown");

        riskParameters[tokenAddress] = RiskParameter({
            maxLeverage: maxLeverage,
            maintenanceMargin: maintenanceMargin,
            liquidationThreshold: liquidationThreshold,
            maxPositionSize: maxPositionSize,
            minCollateral: minCollateral,
            maxDrawdown: maxDrawdown,
            isActive: true
        });

        emit RiskParameterUpdated(tokenAddress, maxLeverage, maintenanceMargin, liquidationThreshold);
    }

    function openPosition(
        address tokenAddress,
        uint256 size,
        uint256 collateral,
        uint256 leverage,
        bool isLong
    ) external nonReentrant whenNotPaused {
        RiskParameter storage params = riskParameters[tokenAddress];
        require(params.isActive, "Risk parameters not set");
        require(leverage <= params.maxLeverage, "Leverage too high");
        require(collateral >= params.minCollateral, "Insufficient collateral");
        require(size <= params.maxPositionSize, "Position too large");

        uint256 positionId = positionCount[msg.sender]++;
        (uint256 entryPrice,,,) = getPriceOracle(tokenAddress);
        uint256 liquidationPrice = isLong ?
            entryPrice * (1e18 - params.liquidationThreshold) / 1e18 :
            entryPrice * (1e18 + params.liquidationThreshold) / 1e18;

        positions[msg.sender][positionId] = Position({
            owner: msg.sender,
            size: size,
            collateral: collateral,
            leverage: leverage,
            entryPrice: entryPrice,
            liquidationPrice: liquidationPrice,
            lastUpdateTime: block.timestamp,
            isLong: isLong,
            isActive: true
        });

        RiskMetrics storage metrics = riskMetrics[tokenAddress];
        metrics.totalPositionSize += size;
        metrics.totalCollateral += collateral;
        metrics.lastUpdateTime = block.timestamp;

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), collateral);
        emit PositionOpened(msg.sender, tokenAddress, positionId, size, collateral, leverage, isLong);
    }

    function closePosition(
        address tokenAddress,
        uint256 positionId
    ) external nonReentrant {
        Position storage position = positions[msg.sender][positionId];
        require(position.isActive, "Position not active");

        (uint256 currentPrice,,,) = getPriceOracle(tokenAddress);
        int256 pnl = calculatePnL(position, currentPrice);
        uint256 pnlAmount;

        position.isActive = false;
        RiskMetrics storage metrics = riskMetrics[tokenAddress];
        metrics.totalPositionSize -= position.size;
        metrics.totalCollateral -= position.collateral;

        if (pnl > 0) {
            pnlAmount = uint256(pnl);
            IERC20(tokenAddress).safeTransfer(msg.sender, position.collateral + pnlAmount);
        } else {
            pnlAmount = uint256(-pnl);
            uint256 remainingCollateral = position.collateral > pnlAmount ?
                position.collateral - pnlAmount : 0;
            if (remainingCollateral > 0) {
                IERC20(tokenAddress).safeTransfer(msg.sender, remainingCollateral);
            }
        }

        emit PositionClosed(msg.sender, tokenAddress, positionId, pnlAmount);
    }

    function liquidatePosition(
        address tokenAddress,
        address owner,
        uint256 positionId
    ) external nonReentrant {
        Position storage position = positions[owner][positionId];
        require(position.isActive, "Position not active");

        (uint256 currentPrice,,,) = getPriceOracle(tokenAddress);
        bool shouldLiquidate = position.isLong ?
            currentPrice <= position.liquidationPrice :
            currentPrice >= position.liquidationPrice;

        require(shouldLiquidate, "Cannot liquidate");

        uint256 deficit = calculateDeficit(position, currentPrice);
        position.isActive = false;

        RiskMetrics storage metrics = riskMetrics[tokenAddress];
        metrics.totalPositionSize -= position.size;
        metrics.totalCollateral -= position.collateral;
        metrics.maxDrawdown = Math.max(metrics.maxDrawdown, deficit);

        // Reward liquidator
        uint256 liquidatorReward = deficit / 10; // 10% of deficit
        if (liquidatorReward > 0) {
            IERC20(tokenAddress).safeTransfer(msg.sender, liquidatorReward);
        }

        emit PositionLiquidated(owner, tokenAddress, positionId, deficit);
    }

    // Liquidity mining functions
    function createLiquidityMiningPool(
        address tokenAddress,
        uint256 rewardRate,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(rewardRate > 0, "Invalid reward rate");
        require(startTime > block.timestamp, "Invalid start time");
        require(endTime > startTime, "Invalid end time");

        liquidityMiningPoolCounter.increment();
        uint256 poolId = liquidityMiningPoolCounter.current();

        liquidityMiningPools[poolId] = LiquidityMiningPool({
            id: poolId,
            token: tokenAddress,
            rewardRate: rewardRate,
            totalLiquidity: 0,
            accumulatedRewardsPerShare: 0,
            lastUpdateTime: block.timestamp,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        emit LiquidityMiningPoolCreated(poolId, tokenAddress, rewardRate, startTime, endTime);
    }

    function provideLiquidityMining(
        uint256 poolId,
        uint256 liquidity
    ) external nonReentrant whenNotPaused {
        LiquidityMiningPool storage pool = liquidityMiningPools[poolId];
        require(pool.isActive, "Pool not active");
        require(block.timestamp >= pool.startTime, "Pool not started");
        require(block.timestamp <= pool.endTime, "Pool ended");
        require(liquidity > 0, "Invalid liquidity");

        updateAccumulatedRewards(poolId);

        MinerPosition storage position = minerPositions[poolId][msg.sender];
        if (position.isActive) {
            claimMiningRewards(poolId);
        }

        position.liquidity += liquidity;
        position.rewardDebt = (position.liquidity * pool.accumulatedRewardsPerShare) / 1e18;
        position.lastUpdateTime = block.timestamp;
        position.isActive = true;

        pool.totalLiquidity += liquidity;
        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), liquidity);

        emit LiquidityMiningPositionOpened(poolId, msg.sender, liquidity);
    }

    function withdrawLiquidityMining(
        uint256 poolId,
        uint256 liquidity
    ) external nonReentrant {
        LiquidityMiningPool storage pool = liquidityMiningPools[poolId];
        MinerPosition storage position = minerPositions[poolId][msg.sender];
        require(position.isActive, "No active position");
        require(liquidity <= position.liquidity, "Insufficient liquidity");

        updateAccumulatedRewards(poolId);
        claimMiningRewards(poolId);

        position.liquidity -= liquidity;
        position.rewardDebt = (position.liquidity * pool.accumulatedRewardsPerShare) / 1e18;

        if (position.liquidity == 0) {
            position.isActive = false;
        }

        pool.totalLiquidity -= liquidity;
        IERC20(pool.token).safeTransfer(msg.sender, liquidity);

        emit LiquidityMiningPositionClosed(poolId, msg.sender, liquidity, 0);
    }

    function claimMiningRewards(uint256 poolId) public nonReentrant {
        LiquidityMiningPool storage pool = liquidityMiningPools[poolId];
        MinerPosition storage position = minerPositions[poolId][msg.sender];
        require(position.isActive, "No active position");

        updateAccumulatedRewards(poolId);

        uint256 pending = (position.liquidity * pool.accumulatedRewardsPerShare) / 1e18 - position.rewardDebt;
        if (pending > 0) {
            position.rewardDebt = (position.liquidity * pool.accumulatedRewardsPerShare) / 1e18;
            IERC20(pool.token).safeTransfer(msg.sender, pending);
            emit LiquidityMiningRewardsClaimed(poolId, msg.sender, pending);
        }
    }

    // Internal functions
    function updateAccumulatedRewards(uint256 poolId) internal {
        LiquidityMiningPool storage pool = liquidityMiningPools[poolId];
        if (pool.totalLiquidity == 0) return;

        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        if (timeElapsed > 0 && pool.totalLiquidity > 0) {
            uint256 rewards = (timeElapsed * pool.rewardRate * 1e18) / pool.totalLiquidity;
            pool.accumulatedRewardsPerShare += rewards;
            pool.lastUpdateTime = block.timestamp;
        }
    }

    function calculatePnL(Position memory position, uint256 currentPrice) internal pure returns (int256) {
        if (position.isLong) {
            return int256((currentPrice - position.entryPrice) * position.size / position.entryPrice);
        } else {
            return int256((position.entryPrice - currentPrice) * position.size / position.entryPrice);
        }
    }

    function calculateDeficit(Position memory position, uint256 currentPrice) internal pure returns (uint256) {
        int256 pnl = calculatePnL(position, currentPrice);
        if (pnl >= 0) return 0;
        uint256 absPnL = uint256(-pnl);
        return absPnL > position.collateral ? absPnL - position.collateral : 0;
    }

    // View functions
    function getRiskParameters(address tokenAddress) external view returns (
        uint256 maxLeverage,
        uint256 maintenanceMargin,
        uint256 liquidationThreshold,
        uint256 maxPositionSize,
        uint256 minCollateral,
        uint256 maxDrawdown,
        bool isActive
    ) {
        RiskParameter storage params = riskParameters[tokenAddress];
        return (
            params.maxLeverage,
            params.maintenanceMargin,
            params.liquidationThreshold,
            params.maxPositionSize,
            params.minCollateral,
            params.maxDrawdown,
            params.isActive
        );
    }

    function getRiskMetrics(address tokenAddress) external view returns (
        uint256 totalPositionSize,
        uint256 totalCollateral,
        uint256 maxDrawdown,
        uint256 volatility,
        uint256 sharpeRatio,
        uint256 lastUpdateTime
    ) {
        RiskMetrics storage metrics = riskMetrics[tokenAddress];
        return (
            metrics.totalPositionSize,
            metrics.totalCollateral,
            metrics.maxDrawdown,
            metrics.volatility,
            metrics.sharpeRatio,
            metrics.lastUpdateTime
        );
    }

    function getLiquidityMiningPool(uint256 poolId) external view returns (
        uint256 id,
        address tokenAddress,
        uint256 rewardRate,
        uint256 totalLiquidity,
        uint256 accumulatedRewardsPerShare,
        uint256 lastUpdateTime,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        LiquidityMiningPool storage pool = liquidityMiningPools[poolId];
        return (
            pool.id,
            pool.token,
            pool.rewardRate,
            pool.totalLiquidity,
            pool.accumulatedRewardsPerShare,
            pool.lastUpdateTime,
            pool.startTime,
            pool.endTime,
            pool.isActive
        );
    }

    function getPosition(
        address owner,
        uint256 positionId
    ) external view returns (
        uint256 size,
        uint256 collateral,
        uint256 leverage,
        uint256 entryPrice,
        uint256 liquidationPrice,
        uint256 lastUpdateTime,
        bool isLong,
        bool isActive
    ) {
        Position storage position = positions[owner][positionId];
        return (
            position.size,
            position.collateral,
            position.leverage,
            position.entryPrice,
            position.liquidationPrice,
            position.lastUpdateTime,
            position.isLong,
            position.isActive
        );
    }

    function getMinerPosition(
        uint256 poolId,
        address miner
    ) external view returns (
        uint256 liquidity,
        uint256 rewardDebt,
        uint256 lastUpdateTime,
        bool isActive
    ) {
        MinerPosition storage position = minerPositions[poolId][miner];
        return (
            position.liquidity,
            position.rewardDebt,
            position.lastUpdateTime,
            position.isActive
        );
    }

    // Advanced cross-chain features
    struct CrossChainBridge {
        address token;
        uint256 chainId;
        uint256 minAmount;
        uint256 maxAmount;
        uint256 fee;
        uint256 dailyLimit;
        uint256 totalTransferred;
        uint256 lastTransferTime;
        bool isActive;
    }

    struct CrossChainTransaction {
        bytes32 txHash;
        address sender;
        address receiver;
        uint256 amount;
        uint256 sourceChainId;
        uint256 targetChainId;
        uint256 bridgeId;  // Added bridgeId field
        uint256 timestamp;
        bool isExecuted;
    }

    // Cross-chain mappings
    mapping(uint256 => CrossChainBridge) public crossChainBridges;
    mapping(bytes32 => CrossChainTransaction) public crossChainTransactions;
    mapping(uint256 => uint256) public dailyTransferLimits;
    Counters.Counter private bridgeCounter;

    // Events for cross-chain features
    event CrossChainBridgeCreated(
        uint256 indexed bridgeId,
        address token,
        uint256 chainId,
        uint256 minAmount,
        uint256 maxAmount
    );
    event CrossChainBridgeUpdated(
        uint256 indexed bridgeId,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee
    );
    event CrossChainBridgeDeactivated(uint256 indexed bridgeId);
    event CrossChainTransferInitiated(
        bytes32 indexed txHash,
        address indexed sender,
        address indexed receiver,
        uint256 amount
    );
    event CrossChainTransferExecuted(
        bytes32 indexed txHash,
        address indexed receiver,
        uint256 amount
    );

    // Cross-chain functions
    function createCrossChainBridge(
        address tokenAddress,  // Changed from token to tokenAddress
        uint256 chainId,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee,
        uint256 dailyLimit
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(chainId > 0, "Invalid chain ID");
        require(minAmount < maxAmount, "Invalid amount range");
        require(fee <= 1000, "Fee too high"); // Max 10%
        require(dailyLimit > 0, "Invalid daily limit");

        bridgeCounter.increment();
        uint256 bridgeId = bridgeCounter.current();

        crossChainBridges[bridgeId] = CrossChainBridge({
            token: tokenAddress,
            chainId: chainId,
            minAmount: minAmount,
            maxAmount: maxAmount,
            fee: fee,
            dailyLimit: dailyLimit,
            totalTransferred: 0,
            lastTransferTime: block.timestamp,
            isActive: true
        });

        emit CrossChainBridgeCreated(bridgeId, tokenAddress, chainId, minAmount, maxAmount);
    }

    function updateCrossChainBridge(
        uint256 bridgeId,
        uint256 minAmount,
        uint256 maxAmount,
        uint256 fee,
        uint256 dailyLimit
    ) external onlyOwner {
        require(bridgeId <= bridgeCounter.current(), "Invalid bridge");
        require(minAmount < maxAmount, "Invalid amount range");
        require(fee <= 1000, "Fee too high");
        require(dailyLimit > 0, "Invalid daily limit");

        CrossChainBridge storage bridge = crossChainBridges[bridgeId];
        require(bridge.isActive, "Bridge not active");

        bridge.minAmount = minAmount;
        bridge.maxAmount = maxAmount;
        bridge.fee = fee;
        bridge.dailyLimit = dailyLimit;

        emit CrossChainBridgeUpdated(bridgeId, minAmount, maxAmount, fee);
    }

    function deactivateCrossChainBridge(uint256 bridgeId) external onlyOwner {
        require(bridgeId <= bridgeCounter.current(), "Invalid bridge");

        CrossChainBridge storage bridge = crossChainBridges[bridgeId];
        require(bridge.isActive, "Bridge not active");

        bridge.isActive = false;
        emit CrossChainBridgeDeactivated(bridgeId);
    }

    function initiateCrossChainTransfer(
        uint256 bridgeId,
        address receiverAddress,  // Changed from receiver to receiverAddress
        uint256 amount,
        uint256 targetChainId
    ) external nonReentrant whenNotPaused {
        require(bridgeId <= bridgeCounter.current(), "Invalid bridge");

        CrossChainBridge storage bridge = crossChainBridges[bridgeId];
        require(bridge.isActive, "Bridge not active");
        require(amount >= bridge.minAmount, "Amount below minimum");
        require(amount <= bridge.maxAmount, "Amount above maximum");
        require(amount <= bridge.dailyLimit, "Exceeds daily limit");
        require(targetChainId != bridge.chainId, "Same chain");

        uint256 fee = (amount * bridge.fee) / 10000;
        uint256 totalAmount = amount + fee;

        IERC20(bridge.token).safeTransferFrom(msg.sender, address(this), totalAmount);

        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            receiverAddress,
            amount,
            bridge.chainId,
            targetChainId,
            block.timestamp
        ));

        crossChainTransactions[txHash] = CrossChainTransaction({
            txHash: txHash,
            sender: msg.sender,
            receiver: receiverAddress,
            amount: amount,
            sourceChainId: bridge.chainId,
            targetChainId: targetChainId,
            bridgeId: bridgeId,
            timestamp: block.timestamp,
            isExecuted: false
        });

        emit CrossChainTransferInitiated(txHash, msg.sender, receiverAddress, amount);
    }

    function executeCrossChainTransfer(
        bytes32 txHash,
        uint256 sourceChainId,
        uint256 targetChainId,
        uint256 amount
    ) external onlyOwner {
        require(txHash != bytes32(0), "Invalid transaction hash");
        require(sourceChainId != targetChainId, "Same chain");

        CrossChainTransaction storage transaction = crossChainTransactions[txHash];
        require(!transaction.isExecuted, "Transaction already executed");

        transaction.isExecuted = true;
        transaction.targetChainId = targetChainId;

        IERC20(crossChainBridges[transaction.bridgeId].token).safeTransfer(transaction.receiver, amount);

        emit CrossChainTransferExecuted(txHash, transaction.receiver, amount);
    }

    // Advanced DeFi Features
    struct YieldStrategy {
        address strategyAddress;  // Changed from 'strategy' to 'strategyAddress'
        uint256 allocation;
        uint256 apy;
        uint256 lastHarvest;
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        bool isActive;
    }

    struct YieldPosition {
        address user;
        uint256 amount;
        uint256 shares;
        uint256 lastUpdate;
        uint256 pendingRewards;
        bool isActive;
    }

    struct YieldMetrics {
        uint256 totalValueLocked;
        uint256 totalRewardsDistributed;
        uint256 averageApy;
        uint256 lastUpdateTime;
        uint256 dailyRewards;
        uint256 weeklyRewards;
        uint256 monthlyRewards;
    }

    // Yield farming mappings
    mapping(uint256 => YieldStrategy) public yieldStrategies;
    mapping(address => mapping(uint256 => YieldPosition)) public yieldPositions;
    mapping(uint256 => YieldMetrics) public yieldMetrics;
    Counters.Counter private strategyCounter;

    // Events for yield farming
    event YieldStrategyCreated(
        uint256 indexed strategyId,
        address strategy,
        uint256 allocation,
        uint256 apy
    );
    event YieldStrategyUpdated(
        uint256 indexed strategyId,
        uint256 allocation,
        uint256 apy
    );
    event YieldStrategyDeactivated(uint256 indexed strategyId);
    event YieldPositionOpened(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount
    );
    event YieldPositionClosed(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount
    );
    event YieldRewardsHarvested(
        address indexed user,
        uint256 indexed strategyId,
        uint256 amount
    );

    // Yield farming functions
    function createYieldStrategy(
        address strategyAddress,
        uint256 allocation,
        uint256 apy
    ) external onlyOwner {
        require(strategyAddress != address(0), "Invalid strategy");
        require(allocation <= 10000, "Invalid allocation"); // Max 100%
        require(apy <= 10000, "Invalid APY"); // Max 100%

        strategyCounter.increment();
        uint256 strategyId = strategyCounter.current();

        yieldStrategies[strategyId] = YieldStrategy({
            strategyAddress: strategyAddress,
            allocation: allocation,
            apy: apy,
            lastHarvest: block.timestamp,
            totalDeposits: 0,
            totalWithdrawals: 0,
            isActive: true
        });

        emit YieldStrategyCreated(strategyId, strategyAddress, allocation, apy);
    }

    function updateYieldStrategy(
        uint256 strategyId,
        uint256 allocation,
        uint256 apy
    ) external onlyOwner {
        require(strategyId <= strategyCounter.current(), "Invalid strategy");
        require(allocation <= 10000, "Invalid allocation");
        require(apy <= 10000, "Invalid APY");

        YieldStrategy storage strategy = yieldStrategies[strategyId];
        require(strategy.isActive, "Strategy not active");

        strategy.allocation = allocation;
        strategy.apy = apy;
        strategy.lastHarvest = block.timestamp;

        emit YieldStrategyUpdated(strategyId, allocation, apy);
    }

    function deactivateYieldStrategy(uint256 strategyId) external onlyOwner {
        require(strategyId <= strategyCounter.current(), "Invalid strategy");

        YieldStrategy storage strategy = yieldStrategies[strategyId];
        require(strategy.isActive, "Strategy not active");

        strategy.isActive = false;
        emit YieldStrategyDeactivated(strategyId);
    }

    function openYieldPosition(
        uint256 strategyId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(strategyId <= strategyCounter.current(), "Invalid strategy");
        require(amount > 0, "Invalid amount");

        YieldStrategy storage strategy = yieldStrategies[strategyId];
        require(strategy.isActive, "Strategy not active");

        token.safeTransferFrom(msg.sender, address(this), amount);

        YieldPosition storage position = yieldPositions[msg.sender][strategyId];
        position.user = msg.sender;
        position.amount += amount;
        position.shares = calculateShares(amount, strategy);
        position.lastUpdate = block.timestamp;
        position.isActive = true;

        strategy.totalDeposits += amount;
        updateYieldMetrics(strategyId, amount, true);

        emit YieldPositionOpened(msg.sender, strategyId, amount);
    }

    function closeYieldPosition(
        uint256 strategyId,
        uint256 amount
    ) external nonReentrant {
        require(strategyId <= strategyCounter.current(), "Invalid strategy");
        require(amount > 0, "Invalid amount");

        YieldStrategy storage strategy = yieldStrategies[strategyId];
        require(strategy.isActive, "Strategy not active");

        YieldPosition storage position = yieldPositions[msg.sender][strategyId];
        require(position.isActive, "Position not active");
        require(position.amount >= amount, "Insufficient balance");

        uint256 rewards = calculatePendingRewards(msg.sender, strategyId);
        position.pendingRewards = 0;
        position.amount -= amount;
        position.shares = calculateShares(position.amount, strategy);
        position.lastUpdate = block.timestamp;

        strategy.totalWithdrawals += amount;
        updateYieldMetrics(strategyId, amount, false);

        token.safeTransfer(msg.sender, amount + rewards);

        emit YieldPositionClosed(msg.sender, strategyId, amount);
    }

    function harvestYieldRewards(uint256 strategyId) external nonReentrant {
        require(strategyId <= strategyCounter.current(), "Invalid strategy");

        YieldStrategy storage strategy = yieldStrategies[strategyId];
        require(strategy.isActive, "Strategy not active");

        YieldPosition storage position = yieldPositions[msg.sender][strategyId];
        require(position.isActive, "Position not active");

        uint256 rewards = calculatePendingRewards(msg.sender, strategyId);
        require(rewards > 0, "No rewards to harvest");

        position.pendingRewards = 0;
        position.lastUpdate = block.timestamp;

        token.safeTransfer(msg.sender, rewards);
        updateYieldMetrics(strategyId, rewards, true);

        emit YieldRewardsHarvested(msg.sender, strategyId, rewards);
    }

    // Advanced trading features
    struct TradingPair {
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
        uint256 lastUpdateTime;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        uint256 kLast;
        uint256 fee;
        bool isActive;
    }

    struct TradingPosition {
        address user;
        uint256 amount0;
        uint256 amount1;
        uint256 liquidity;
        uint256 lastUpdateTime;
        uint256 pendingFees0;
        uint256 pendingFees1;
        bool isActive;
    }

    // Trading mappings
    mapping(uint256 => TradingPair) public tradingPairs;
    mapping(address => mapping(uint256 => TradingPosition)) public tradingPositions;
    Counters.Counter private pairCounter;

    // Events for trading
    event TradingPairCreated(
        uint256 indexed pairId,
        address token0,
        address token1,
        uint256 fee
    );
    event TradingPairUpdated(
        uint256 indexed pairId,
        uint256 reserve0,
        uint256 reserve1
    );
    event TradingPairDeactivated(uint256 indexed pairId);
    event TradingPositionOpened(
        address indexed user,
        uint256 indexed pairId,
        uint256 amount0,
        uint256 amount1
    );
    event TradingPositionClosed(
        address indexed user,
        uint256 indexed pairId,
        uint256 amount0,
        uint256 amount1
    );
    event TradingFeesCollected(
        address indexed user,
        uint256 indexed pairId,
        uint256 amount0,
        uint256 amount1
    );

    // Trading functions
    function createTradingPair(
        address token0Address,  // Changed from token0 to token0Address
        address token1Address,  // Changed from token1 to token1Address
        uint256 fee
    ) external onlyOwner {
        require(token0Address != address(0) && token1Address != address(0), "Invalid tokens");
        require(token0Address != token1Address, "Same token");
        require(fee <= 1000, "Fee too high"); // Max 1%

        pairCounter.increment();
        uint256 pairId = pairCounter.current();

        tradingPairs[pairId] = TradingPair({
            token0: token0Address,
            token1: token1Address,
            reserve0: 0,
            reserve1: 0,
            lastUpdateTime: block.timestamp,
            price0CumulativeLast: 0,
            price1CumulativeLast: 0,
            kLast: 0,
            fee: fee,
            isActive: true
        });

        emit TradingPairCreated(pairId, token0Address, token1Address, fee);
    }

    function updateTradingPair(
        uint256 pairId,
        uint256 reserve0,
        uint256 reserve1
    ) external onlyOwner {
        require(pairId <= pairCounter.current(), "Invalid pair");
        require(reserve0 > 0 && reserve1 > 0, "Invalid reserves");

        TradingPair storage pair = tradingPairs[pairId];
        require(pair.isActive, "Pair not active");

        pair.reserve0 = reserve0;
        pair.reserve1 = reserve1;
        pair.lastUpdateTime = block.timestamp;

        emit TradingPairUpdated(pairId, reserve0, reserve1);
    }

    function deactivateTradingPair(uint256 pairId) external onlyOwner {
        require(pairId <= pairCounter.current(), "Invalid pair");

        TradingPair storage pair = tradingPairs[pairId];
        require(pair.isActive, "Pair not active");

        pair.isActive = false;
        emit TradingPairDeactivated(pairId);
    }

    function openTradingPosition(
        uint256 pairId,
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant whenNotPaused {
        require(pairId <= pairCounter.current(), "Invalid pair");
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");

        TradingPair storage pair = tradingPairs[pairId];
        require(pair.isActive, "Pair not active");

        IERC20(pair.token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(pair.token1).safeTransferFrom(msg.sender, address(this), amount1);

        TradingPosition storage position = tradingPositions[msg.sender][pairId];
        position.user = msg.sender;
        position.amount0 += amount0;
        position.amount1 += amount1;
        position.liquidity = calculateLiquidity(amount0, amount1);
        position.lastUpdateTime = block.timestamp;
        position.isActive = true;

        pair.reserve0 += amount0;
        pair.reserve1 += amount1;

        emit TradingPositionOpened(msg.sender, pairId, amount0, amount1);
    }

    function closeTradingPosition(
        uint256 pairId,
        uint256 amount0,
        uint256 amount1
    ) external nonReentrant {
        require(pairId <= pairCounter.current(), "Invalid pair");
        require(amount0 > 0 && amount1 > 0, "Invalid amounts");

        TradingPair storage pair = tradingPairs[pairId];
        require(pair.isActive, "Pair not active");

        TradingPosition storage position = tradingPositions[msg.sender][pairId];
        require(position.isActive, "Position not active");
        require(position.amount0 >= amount0 && position.amount1 >= amount1, "Insufficient balance");

        uint256 fees0 = calculatePendingFees0(msg.sender, pairId);
        uint256 fees1 = calculatePendingFees1(msg.sender, pairId);

        position.amount0 -= amount0;
        position.amount1 -= amount1;
        position.liquidity = calculateLiquidity(position.amount0, position.amount1);
        position.lastUpdateTime = block.timestamp;
        position.pendingFees0 = 0;
        position.pendingFees1 = 0;

        pair.reserve0 -= amount0;
        pair.reserve1 -= amount1;

        IERC20(pair.token0).safeTransfer(msg.sender, amount0 + fees0);
        IERC20(pair.token1).safeTransfer(msg.sender, amount1 + fees1);

        emit TradingPositionClosed(msg.sender, pairId, amount0, amount1);
    }

    function collectTradingFees(uint256 pairId) external nonReentrant {
        require(pairId <= pairCounter.current(), "Invalid pair");

        TradingPair storage pair = tradingPairs[pairId];
        require(pair.isActive, "Pair not active");

        TradingPosition storage position = tradingPositions[msg.sender][pairId];
        require(position.isActive, "Position not active");

        uint256 fees0 = calculatePendingFees0(msg.sender, pairId);
        uint256 fees1 = calculatePendingFees1(msg.sender, pairId);
        require(fees0 > 0 || fees1 > 0, "No fees to collect");

        position.pendingFees0 = 0;
        position.pendingFees1 = 0;
        position.lastUpdateTime = block.timestamp;

        IERC20(pair.token0).safeTransfer(msg.sender, fees0);
        IERC20(pair.token1).safeTransfer(msg.sender, fees1);

        emit TradingFeesCollected(msg.sender, pairId, fees0, fees1);
    }

    // Advanced lending features
    struct LendingPool {
        address tokenAddress;  // Changed from 'token' to 'tokenAddress'
        uint256 totalSupply;
        uint256 totalBorrow;
        uint256 reserveFactor;
        uint256 interestRate;
        uint256 lastUpdateTime;
        uint256 exchangeRate;
        bool isActive;
    }

    struct LendingPosition {
        address user;
        uint256 supply;
        uint256 borrow;
        uint256 lastUpdateTime;
        uint256 pendingRewards;
        bool isActive;
    }

    // Lending mappings
    mapping(uint256 => LendingPool) public lendingPools;
    mapping(address => mapping(uint256 => LendingPosition)) public lendingPositions;
    
    // Events for lending
    event LendingPoolCreated(
        uint256 indexed poolId,
        address token,
        uint256 reserveFactor,
        uint256 interestRate
    );
    event LendingPoolUpdated(
        uint256 indexed poolId,
        uint256 reserveFactor,
        uint256 interestRate
    );
    event LendingPoolDeactivated(uint256 indexed poolId);
    event LendingPositionOpened(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event LendingPositionClosed(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );
    event LendingRewardsCollected(
        address indexed user,
        uint256 indexed poolId,
        uint256 amount
    );

    // Lending functions
    function createLendingPool(
        address tokenAddress,  // Changed from token to tokenAddress
        uint256 reserveFactor,
        uint256 interestRate
    ) external onlyOwner {
        require(tokenAddress != address(0), "Invalid token");
        require(reserveFactor <= 10000, "Invalid reserve factor"); // Max 100%
        require(interestRate <= 10000, "Invalid interest rate"); // Max 100%

        poolCounter.increment();
        uint256 poolId = poolCounter.current();

        lendingPools[poolId] = LendingPool({
            tokenAddress: tokenAddress,  // Use tokenAddress here
            totalSupply: 0,
            totalBorrow: 0,
            reserveFactor: reserveFactor,
            interestRate: interestRate,
            lastUpdateTime: block.timestamp,
            exchangeRate: 1e18,
            isActive: true
        });

        emit LendingPoolCreated(poolId, tokenAddress, reserveFactor, interestRate);
    }

    function updateLendingPool(
        uint256 poolId,
        uint256 reserveFactor,
        uint256 interestRate
    ) external onlyOwner {
        require(poolId <= poolCounter.current(), "Invalid pool");
        require(reserveFactor <= 10000, "Invalid reserve factor");
        require(interestRate <= 10000, "Invalid interest rate");

        LendingPool storage pool = lendingPools[poolId];
        require(pool.isActive, "Pool not active");

        pool.reserveFactor = reserveFactor;
        pool.interestRate = interestRate;
        pool.lastUpdateTime = block.timestamp;

        emit LendingPoolUpdated(poolId, reserveFactor, interestRate);
    }

    function deactivateLendingPool(uint256 poolId) external onlyOwner {
        require(poolId <= poolCounter.current(), "Invalid pool");

        LendingPool storage pool = lendingPools[poolId];
        require(pool.isActive, "Pool not active");

        pool.isActive = false;
        emit LendingPoolDeactivated(poolId);
    }

    function openLendingPosition(
        uint256 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(poolId <= poolCounter.current(), "Invalid pool");
        require(amount > 0, "Invalid amount");

        LendingPool storage pool = lendingPools[poolId];
        require(pool.isActive, "Pool not active");

        IERC20(pool.tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        LendingPosition storage position = lendingPositions[msg.sender][poolId];
        position.user = msg.sender;
        position.supply += amount;
        position.lastUpdateTime = block.timestamp;
        position.isActive = true;

        pool.totalSupply += amount;
        updateLendingPoolState(poolId);

        emit LendingPositionOpened(msg.sender, poolId, amount);
    }

    function closeLendingPosition(
        uint256 poolId,
        uint256 amount
    ) external nonReentrant {
        require(poolId <= poolCounter.current(), "Invalid pool");
        require(amount > 0, "Invalid amount");

        LendingPool storage pool = lendingPools[poolId];
        require(pool.isActive, "Pool not active");

        LendingPosition storage position = lendingPositions[msg.sender][poolId];
        require(position.isActive, "Position not active");
        require(position.supply >= amount, "Insufficient balance");

        uint256 rewards = calculatePendingLendingRewards(msg.sender, poolId);
        position.pendingRewards = 0;
        position.supply -= amount;
        position.lastUpdateTime = block.timestamp;

        pool.totalSupply -= amount;
        updateLendingPoolState(poolId);

        IERC20(pool.tokenAddress).safeTransfer(msg.sender, amount + rewards);

        emit LendingPositionClosed(msg.sender, poolId, amount);
    }

    function collectLendingRewards(uint256 poolId) external nonReentrant {
        require(poolId <= poolCounter.current(), "Invalid pool");

        LendingPool storage pool = lendingPools[poolId];
        require(pool.isActive, "Pool not active");

        LendingPosition storage position = lendingPositions[msg.sender][poolId];
        require(position.isActive, "Position not active");

        uint256 rewards = calculatePendingLendingRewards(msg.sender, poolId);
        require(rewards > 0, "No rewards to collect");

        position.pendingRewards = 0;
        position.lastUpdateTime = block.timestamp;

        IERC20(pool.tokenAddress).safeTransfer(msg.sender, rewards);
        updateLendingPoolState(poolId);

        emit LendingRewardsCollected(msg.sender, poolId, rewards);
    }

    // Helper functions
    function calculateShares(
        uint256 amount,
        YieldStrategy storage strategy
    ) internal view returns (uint256) {  // Changed from pure to view since it reads from storage
        return amount * strategy.apy / 10000;
    }

    function calculateLiquidity(
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256) {
        return Math.sqrt(amount0 * amount1);
    }

    function calculatePendingRewards(
        address user,
        uint256 strategyId
    ) internal view returns (uint256) {
        YieldPosition storage position = yieldPositions[user][strategyId];
        YieldStrategy storage strategy = yieldStrategies[strategyId];
        
        if (!position.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - position.lastUpdate;
        return (position.amount * strategy.apy * timeElapsed) / (365 days * 10000);
    }

    function calculatePendingFees0(
        address user,
        uint256 pairId
    ) internal view returns (uint256) {
        TradingPosition storage position = tradingPositions[user][pairId];
        TradingPair storage pair = tradingPairs[pairId];
        
        if (!position.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        return (position.amount0 * pair.fee * timeElapsed) / (365 days * 10000);
    }

    function calculatePendingFees1(
        address user,
        uint256 pairId
    ) internal view returns (uint256) {
        TradingPosition storage position = tradingPositions[user][pairId];
        TradingPair storage pair = tradingPairs[pairId];
        
        if (!position.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        return (position.amount1 * pair.fee * timeElapsed) / (365 days * 10000);
    }

    function calculatePendingLendingRewards(
        address user,
        uint256 poolId
    ) internal view returns (uint256) {
        LendingPosition storage position = lendingPositions[user][poolId];
        LendingPool storage pool = lendingPools[poolId];
        
        if (!position.isActive) return 0;
        
        uint256 timeElapsed = block.timestamp - position.lastUpdateTime;
        return (position.supply * pool.interestRate * timeElapsed) / (365 days * 10000);
    }

    function updateYieldMetrics(
        uint256 strategyId,
        uint256 amount,
        bool isDeposit
    ) internal {
        YieldMetrics storage metrics = yieldMetrics[strategyId];
        
        if (isDeposit) {
            metrics.totalValueLocked += amount;
            metrics.dailyRewards += amount;
            metrics.weeklyRewards += amount;
            metrics.monthlyRewards += amount;
        } else {
            metrics.totalValueLocked -= amount;
        }
        
        metrics.lastUpdateTime = block.timestamp;
    }

    function updateLendingPoolState(uint256 poolId) internal {
        LendingPool storage pool = lendingPools[poolId];
        
        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        uint256 interestAccrued = (pool.totalBorrow * pool.interestRate * timeElapsed) / (365 days * 10000);
        
        pool.totalBorrow += interestAccrued;
        pool.exchangeRate = (pool.totalSupply * 1e18) / (pool.totalSupply + interestAccrued);
        pool.lastUpdateTime = block.timestamp;
    }

    // Advanced MEV protection features
    struct MEVProtection {
        uint256 maxSlippage;
        uint256 minLiquidity;
        uint256 maxGasPrice;
        uint256 maxPriorityFee;
        bool isActive;
    }

    struct TransactionProtection {
        uint256 timestamp;
        uint256 gasPrice;
        uint256 priorityFee;
        uint256 slippage;
        bool isProtected;
    }

    // MEV protection mappings
    mapping(address => MEVProtection) public mevProtections;
    mapping(bytes32 => TransactionProtection) public transactionProtections;
    
    // Events for MEV protection
    event MEVProtectionEnabled(address indexed user, uint256 maxSlippage, uint256 maxGasPrice);
    event MEVProtectionDisabled(address indexed user);
    event TransactionProtected(bytes32 indexed txHash, uint256 gasPrice, uint256 slippage);
    
    // MEV protection functions
    function enableMEVProtection(
        uint256 maxSlippage,
        uint256 minLiquidity,
        uint256 maxGasPrice,
        uint256 maxPriorityFee
    ) external {
        require(maxSlippage <= 1000, "Slippage too high"); // Max 10%
        require(minLiquidity > 0, "Invalid liquidity");
        require(maxGasPrice > 0, "Invalid gas price");
        require(maxPriorityFee <= maxGasPrice, "Invalid priority fee");
        
        mevProtections[msg.sender] = MEVProtection({
            maxSlippage: maxSlippage,
            minLiquidity: minLiquidity,
            maxGasPrice: maxGasPrice,
            maxPriorityFee: maxPriorityFee,
            isActive: true
        });
        
        emit MEVProtectionEnabled(msg.sender, maxSlippage, maxGasPrice);
    }
    
    function disableMEVProtection() external {
        require(mevProtections[msg.sender].isActive, "Protection not active");
        
        mevProtections[msg.sender].isActive = false;
        emit MEVProtectionDisabled(msg.sender);
    }
    
    function protectTransaction(
        bytes32 txHash,
        uint256 gasPrice,
        uint256 priorityFee,
        uint256 slippage
    ) external {
        MEVProtection storage protection = mevProtections[msg.sender];
        require(protection.isActive, "Protection not active");
        require(gasPrice <= protection.maxGasPrice, "Gas price too high");
        require(priorityFee <= protection.maxPriorityFee, "Priority fee too high");
        require(slippage <= protection.maxSlippage, "Slippage too high");
        
        transactionProtections[txHash] = TransactionProtection({
            timestamp: block.timestamp,
            gasPrice: gasPrice,
            priorityFee: priorityFee,
            slippage: slippage,
            isProtected: true
        });
        
        emit TransactionProtected(txHash, gasPrice, slippage);
    }
    
    // Advanced oracle features
    struct OracleConfig {
        address oracleAddress;
        uint256 heartbeat;
        uint256 deviation;
        uint256 decimals;
        bool isActive;
    }
    
    struct OracleData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        bool isValid;
    }
    
    // Oracle mappings
    mapping(address => OracleConfig) public oracleConfigs;
    mapping(address => OracleData) public oracleData;
    
    // Events for oracle
    event OracleAdded(address indexed token, address oracle);
    event OracleUpdated(address indexed token, uint256 price);
    event OracleDeactivated(address indexed token);
    
    // Oracle functions
    function addOracle(
        address token,
        address oracleAddress,
        uint256 heartbeat,
        uint256 deviation,
        uint256 decimals
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(oracleAddress != address(0), "Invalid oracle");
        require(heartbeat > 0, "Invalid heartbeat");
        require(deviation <= 1000, "Deviation too high"); // Max 10%
        require(decimals <= 18, "Invalid decimals");
        
        oracleConfigs[token] = OracleConfig({
            oracleAddress: oracleAddress,
            heartbeat: heartbeat,
            deviation: deviation,
            decimals: decimals,
            isActive: true
        });
        
        emit OracleAdded(token, oracleAddress);
    }
    
    function updateOracle(
        address token,
        uint256 price,
        uint256 confidence
    ) external {
        OracleConfig storage config = oracleConfigs[token];
        require(config.isActive, "Oracle not active");
        require(msg.sender == config.oracleAddress, "Not authorized");
        
        OracleData storage data = oracleData[token];
        require(
            block.timestamp - data.timestamp <= config.heartbeat,
            "Heartbeat exceeded"
        );
        
        uint256 deviation = calculateDeviation(data.price, price);
        require(deviation <= config.deviation, "Deviation too high");
        
        data.price = price;
        data.timestamp = block.timestamp;
        data.confidence = confidence;
        data.isValid = true;
        
        emit OracleUpdated(token, price);
    }
    
    function deactivateOracle(address token) external onlyOwner {
        OracleConfig storage config = oracleConfigs[token];
        require(config.isActive, "Oracle not active");
        
        config.isActive = false;
        emit OracleDeactivated(token);
    }
    
    // Advanced insurance features
    struct InsurancePool {
        address token;
        uint256 totalCoverage;
        uint256 totalPremiums;
        uint256 claimRatio;
        uint256 premiumRate;
        bool isActive;
    }
    
    struct InsurancePolicy {
        address holder;
        uint256 coverage;
        uint256 premium;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }
    
    // Insurance mappings
    mapping(uint256 => InsurancePool) public insurancePools;
    mapping(address => mapping(uint256 => InsurancePolicy)) public insurancePolicies;
    Counters.Counter private insurancePoolCounter;
    
    // Events for insurance
    event InsurancePoolCreated(
        uint256 indexed poolId,
        address token,
        uint256 premiumRate
    );
    event InsurancePoolUpdated(
        uint256 indexed poolId,
        uint256 claimRatio,
        uint256 premiumRate
    );
    event InsurancePoolDeactivated(uint256 indexed poolId);
    event InsurancePolicyPurchased(
        address indexed holder,
        uint256 indexed poolId,
        uint256 coverage
    );
    event InsuranceClaimFiled(
        address indexed holder,
        uint256 indexed poolId,
        uint256 amount
    );
    
    // Insurance functions
    function createInsurancePool(
        address token,
        uint256 premiumRate,
        uint256 claimRatio
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(premiumRate <= 1000, "Premium rate too high"); // Max 10%
        require(claimRatio <= 10000, "Claim ratio too high"); // Max 100%
        
        insurancePoolCounter.increment();
        uint256 poolId = insurancePoolCounter.current();
        
        insurancePools[poolId] = InsurancePool({
            token: token,
            totalCoverage: 0,
            totalPremiums: 0,
            claimRatio: claimRatio,
            premiumRate: premiumRate,
            isActive: true
        });
        
        emit InsurancePoolCreated(poolId, token, premiumRate);
    }
    
    function updateInsurancePool(
        uint256 poolId,
        uint256 claimRatio,
        uint256 premiumRate
    ) external onlyOwner {
        require(poolId <= insurancePoolCounter.current(), "Invalid pool");
        require(claimRatio <= 10000, "Claim ratio too high");
        require(premiumRate <= 1000, "Premium rate too high");
        
        InsurancePool storage pool = insurancePools[poolId];
        require(pool.isActive, "Pool not active");
        
        pool.claimRatio = claimRatio;
        pool.premiumRate = premiumRate;
        
        emit InsurancePoolUpdated(poolId, claimRatio, premiumRate);
    }
    
    function deactivateInsurancePool(uint256 poolId) external onlyOwner {
        require(poolId <= insurancePoolCounter.current(), "Invalid pool");
        
        InsurancePool storage pool = insurancePools[poolId];
        require(pool.isActive, "Pool not active");
        
        pool.isActive = false;
        emit InsurancePoolDeactivated(poolId);
    }
    
    function purchaseInsurance(
        uint256 poolId,
        uint256 coverage
    ) external nonReentrant whenNotPaused {
        require(poolId <= insurancePoolCounter.current(), "Invalid pool");
        require(coverage > 0, "Invalid coverage");
        
        InsurancePool storage pool = insurancePools[poolId];
        require(pool.isActive, "Pool not active");
        
        uint256 premium = (coverage * pool.premiumRate) / 10000;
        require(premium > 0, "Invalid premium");
        
        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), premium);
        
        InsurancePolicy storage policy = insurancePolicies[msg.sender][poolId];
        policy.holder = msg.sender;
        policy.coverage = coverage;
        policy.premium = premium;
        policy.startTime = block.timestamp;
        policy.endTime = block.timestamp + 365 days;
        policy.isActive = true;
        
        pool.totalCoverage += coverage;
        pool.totalPremiums += premium;
        
        emit InsurancePolicyPurchased(msg.sender, poolId, coverage);
    }
    
    function fileInsuranceClaim(
        uint256 poolId,
        uint256 amount
    ) external nonReentrant {
        require(poolId <= insurancePoolCounter.current(), "Invalid pool");
        require(amount > 0, "Invalid amount");
        
        InsurancePool storage pool = insurancePools[poolId];
        require(pool.isActive, "Pool not active");
        
        InsurancePolicy storage policy = insurancePolicies[msg.sender][poolId];
        require(policy.isActive, "Policy not active");
        require(block.timestamp <= policy.endTime, "Policy expired");
        require(amount <= policy.coverage, "Amount exceeds coverage");
        
        uint256 maxClaim = (pool.totalPremiums * pool.claimRatio) / 10000;
        require(amount <= maxClaim, "Amount exceeds pool capacity");
        
        policy.coverage -= amount;
        pool.totalCoverage -= amount;
        
        IERC20(pool.token).safeTransfer(msg.sender, amount);
        
        emit InsuranceClaimFiled(msg.sender, poolId, amount);
    }
    
    // Helper functions
    function calculateDeviation(
        uint256 oldPrice,
        uint256 newPrice
    ) internal pure returns (uint256) {
        if (oldPrice == 0) return 0;
        uint256 diff = oldPrice > newPrice ? oldPrice - newPrice : newPrice - oldPrice;
        return (diff * 10000) / oldPrice;
    }

    // Advanced NFT staking features
    struct NFTStake {
        address nftContract;
        uint256 tokenId;
        uint256 stakedAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 boostMultiplier;
        bool isActive;
    }

    struct NFTStakingPool {
        address nftContract;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 minStakeDuration;
        uint256 maxStakeDuration;
        bool isActive;
    }

    // NFT staking mappings
    mapping(address => mapping(uint256 => NFTStake)) public nftStakes;
    mapping(address => NFTStakingPool) public nftStakingPools;
    
    // Events for NFT staking
    event NFTStakingPoolCreated(
        address indexed nftContract,
        uint256 rewardRate,
        uint256 minStakeDuration
    );
    event NFTStaked(
        address indexed user,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 amount
    );
    event NFTUnstaked(
        address indexed user,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 amount
    );
    
    // NFT staking functions
    function createNFTStakingPool(
        address nftContract,
        uint256 rewardRate,
        uint256 minStakeDuration,
        uint256 maxStakeDuration
    ) external onlyOwner {
        require(nftContract != address(0), "Invalid NFT contract");
        require(rewardRate > 0, "Invalid reward rate");
        require(minStakeDuration > 0, "Invalid min duration");
        require(maxStakeDuration > minStakeDuration, "Invalid max duration");
        
        nftStakingPools[nftContract] = NFTStakingPool({
            nftContract: nftContract,
            totalStaked: 0,
            rewardRate: rewardRate,
            minStakeDuration: minStakeDuration,
            maxStakeDuration: maxStakeDuration,
            isActive: true
        });
        
        emit NFTStakingPoolCreated(nftContract, rewardRate, minStakeDuration);
    }
    
    function stakeNFT(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 duration
    ) external nonReentrant whenNotPaused {
        NFTStakingPool storage pool = nftStakingPools[nftContract];
        require(pool.isActive, "Pool not active");
        require(duration >= pool.minStakeDuration, "Duration too short");
        require(duration <= pool.maxStakeDuration, "Duration too long");
        require(amount > 0, "Invalid amount");
        
        NFTStake storage stake = nftStakes[msg.sender][tokenId];
        require(!stake.isActive, "Already staked");
        
        // Calculate boost multiplier based on duration
        uint256 boostMultiplier = calculateBoostMultiplier(duration);
        
        // Transfer NFT to contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        
        stake.nftContract = nftContract;
        stake.tokenId = tokenId;
        stake.stakedAmount = amount;
        stake.startTime = block.timestamp;
        stake.endTime = block.timestamp + duration;
        stake.boostMultiplier = boostMultiplier;
        stake.isActive = true;
        
        pool.totalStaked += amount;
        
        emit NFTStaked(msg.sender, nftContract, tokenId, amount);
    }
    
    function unstakeNFT(
        address nftContract,
        uint256 tokenId
    ) external nonReentrant {
        NFTStake storage stake = nftStakes[msg.sender][tokenId];
        require(stake.isActive, "Not staked");
        require(block.timestamp >= stake.endTime, "Stake not ended");
        
        NFTStakingPool storage pool = nftStakingPools[nftContract];
        require(pool.isActive, "Pool not active");
        
        uint256 reward = calculateNFTStakingReward(stake);
        
        // Transfer NFT back to user
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, tokenId);
        
        // Transfer rewards
        if (reward > 0) {
            token.safeTransfer(msg.sender, reward);
        }
        
        pool.totalStaked -= stake.stakedAmount;
        delete nftStakes[msg.sender][tokenId];
        
        emit NFTUnstaked(msg.sender, nftContract, tokenId, stake.stakedAmount);
    }
    
    // Advanced cross-chain features
    struct CrossChainTransfer {
        address sourceChain;
        address targetChain;
        address token;
        uint256 amount;
        uint256 fee;
        uint256 timestamp;
        bool isCompleted;
    }
    
    // Cross-chain mappings
    mapping(bytes32 => CrossChainTransfer) public crossChainTransfers;
    
    // Events for cross-chain
    event CrossChainTransferInitiated(
        bytes32 indexed transferId,
        address indexed user,
        address sourceChain,
        address targetChain,
        uint256 amount
    );
    event CrossChainTransferCompleted(
        bytes32 indexed transferId,
        address indexed user,
        uint256 amount
    );
    
    // Cross-chain functions
    function initiateCrossChainTransfer(
        address targetChain,
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(targetChain != address(0), "Invalid target chain");
        require(token != address(0), "Invalid token");
        require(amount > 0, "Invalid amount");
        
        uint256 fee = calculateCrossChainFee(amount);
        require(fee < amount, "Fee too high");
        
        bytes32 transferId = keccak256(
            abi.encodePacked(
                msg.sender,
                targetChain,
                token,
                amount,
                block.timestamp
            )
        );
        
        crossChainTransfers[transferId] = CrossChainTransfer({
            sourceChain: address(this),
            targetChain: targetChain,
            token: token,
            amount: amount,
            fee: fee,
            timestamp: block.timestamp,
            isCompleted: false
        });
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        emit CrossChainTransferInitiated(
            transferId,
            msg.sender,
            address(this),
            targetChain,
            amount
        );
    }
    
    function completeCrossChainTransfer(
        bytes32 transferId
    ) external nonReentrant {
        CrossChainTransfer storage transfer = crossChainTransfers[transferId];
        require(!transfer.isCompleted, "Transfer already completed");
        require(block.timestamp <= transfer.timestamp + 24 hours, "Transfer expired");
        
        transfer.isCompleted = true;
        
        uint256 amountAfterFee = transfer.amount - transfer.fee;
        IERC20(transfer.token).safeTransfer(msg.sender, amountAfterFee);
        
        emit CrossChainTransferCompleted(transferId, msg.sender, amountAfterFee);
    }
    
    // Helper functions
    function calculateBoostMultiplier(
        uint256 duration
    ) internal pure returns (uint256) {
        if (duration <= 30 days) return 10000; // 1x
        if (duration <= 90 days) return 12000; // 1.2x
        if (duration <= 180 days) return 15000; // 1.5x
        return 20000; // 2x
    }
    
    function calculateNFTStakingReward(
        NFTStake memory stake
    ) internal view returns (uint256) {
        NFTStakingPool storage pool = nftStakingPools[stake.nftContract];
        uint256 duration = stake.endTime - stake.startTime;
        return (stake.stakedAmount * pool.rewardRate * duration * stake.boostMultiplier) / (365 days * 10000);
    }
    
    function calculateCrossChainFee(
        uint256 amount
    ) internal pure returns (uint256) {
        if (amount <= 1000 ether) return (amount * 50) / 10000; // 0.5%
        if (amount <= 10000 ether) return (amount * 30) / 10000; // 0.3%
        return (amount * 20) / 10000; // 0.2%
    }

    // Token Lock structures
    struct TokenLock {
        uint256 amount;
        uint256 unlockTime;
        bool isActive;
    }

    // Token Lock variables
    mapping(address => TokenLock) public tokenLocks;

    // Token Lock events
    event TokensLocked(address indexed user, uint256 amount, uint256 unlockTime);
    event TokensUnlocked(address indexed user, uint256 amount);

    // Token Lock functions
    function lockTokens(uint256 amount, uint256 lockDuration) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(lockDuration > 0, "Lock duration must be positive");
        require(!tokenLocks[msg.sender].isActive, "Tokens already locked");

        token.safeTransferFrom(msg.sender, address(this), amount);

        tokenLocks[msg.sender] = TokenLock({
            amount: amount,
            unlockTime: block.timestamp + lockDuration,
            isActive: true
        });

        emit TokensLocked(msg.sender, amount, block.timestamp + lockDuration);
    }

    function unlockTokens() external nonReentrant {
        TokenLock storage lock = tokenLocks[msg.sender];
        require(lock.isActive, "No active lock");
        require(block.timestamp >= lock.unlockTime, "Lock period not ended");

        uint256 amount = lock.amount;
        lock.isActive = false;
        lock.amount = 0;

        token.safeTransfer(msg.sender, amount);
        emit TokensUnlocked(msg.sender, amount);
    }

    function getLockInfo(address user) external view returns (
        uint256 amount,
        uint256 unlockTime,
        bool isActive
    ) {
        TokenLock storage lock = tokenLocks[user];
        return (lock.amount, lock.unlockTime, lock.isActive);
    }

    // Referral structures
    struct ReferralInfo {
        address referrer;
        uint256 totalReferrals;
        uint256 totalRewards;
    }

    // Referral variables
    mapping(address => ReferralInfo) public referrals;
    mapping(address => address) public referrers;
    uint256 public constant REFERRAL_REWARD_PERCENT = 100; // 1%

    // Referral events
    event ReferralRegistered(address indexed user, address indexed referrer);
    event ReferralRewardPaid(address indexed referrer, uint256 amount);

    // Referral functions
    function registerReferral(address referrer) external {
        require(referrer != address(0), "Invalid referrer");
        require(referrer != msg.sender, "Cannot refer yourself");
        require(referrers[msg.sender] == address(0), "Already referred");

        referrers[msg.sender] = referrer;
        referrals[referrer].totalReferrals += 1;

        emit ReferralRegistered(msg.sender, referrer);
    }

    function processReferralReward(address user, uint256 amount) internal {
        address referrer = referrers[user];
        if (referrer != address(0)) {
            uint256 reward = (amount * REFERRAL_REWARD_PERCENT) / 10000;
            if (reward > 0) {
                token.safeTransfer(referrer, reward);
                referrals[referrer].totalRewards += reward;
                emit ReferralRewardPaid(referrer, reward);
            }
        }
    }

    function getReferralInfo(address user) external view returns (
        address referrer,
        uint256 totalReferrals,
        uint256 totalRewards
    ) {
        ReferralInfo storage info = referrals[user];
        return (info.referrer, info.totalReferrals, info.totalRewards);
    }

    // Token Burn variables
    address public burnAddress;
    uint256 public totalBurned;

    // Token Burn events
    event TokensBurned(address indexed burner, uint256 amount);
    event BurnAddressSet(address indexed newBurnAddress);

    // Token Burn functions
    function setBurnAddress(address _burnAddress) external onlyOwner {
        require(_burnAddress != address(0), "Invalid burn address");
        burnAddress = _burnAddress;
        emit BurnAddressSet(_burnAddress);
    }

    function burnTokens(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(burnAddress != address(0), "Burn address not set");

        token.safeTransferFrom(msg.sender, burnAddress, amount);
        totalBurned += amount;

        emit TokensBurned(msg.sender, amount);
    }

    function getBurnStats() external view returns (address, uint256) {
        return (burnAddress, totalBurned);
    }

    // Vesting structures
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 duration;
        uint256 cliff;
        bool isActive;
    }

    // Vesting variables
    mapping(address => VestingSchedule) public vestingSchedules;

    // Vesting events
    event VestingScheduleCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);

    // Vesting functions
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 duration,
        uint256 cliff
    ) external onlyOwner {
        require(beneficiary != address(0), "Invalid beneficiary");
        require(amount > 0, "Amount must be positive");
        require(duration > 0, "Duration must be positive");
        require(cliff <= duration, "Cliff must be less than duration");
        require(!vestingSchedules[beneficiary].isActive, "Vesting already exists");

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            releasedAmount: 0,
            startTime: block.timestamp,
            duration: duration,
            cliff: cliff,
            isActive: true
        });

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit VestingScheduleCreated(beneficiary, amount, block.timestamp, duration, cliff);
    }

    function releaseVestedTokens() external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.isActive, "No active vesting");
        require(block.timestamp >= schedule.startTime + schedule.cliff, "Cliff not reached");

        uint256 releasable = calculateReleasableAmount(msg.sender);
        require(releasable > 0, "No tokens to release");

        schedule.releasedAmount += releasable;
        if (schedule.releasedAmount >= schedule.totalAmount) {
            schedule.isActive = false;
        }

        token.safeTransfer(msg.sender, releasable);
        emit TokensReleased(msg.sender, releasable);
    }

    function calculateReleasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        if (!schedule.isActive || block.timestamp < schedule.startTime + schedule.cliff) {
            return 0;
        }

        if (block.timestamp >= schedule.startTime + schedule.duration) {
            return schedule.totalAmount - schedule.releasedAmount;
        }

        uint256 elapsedTime = block.timestamp - schedule.startTime;
        uint256 vestedAmount = (schedule.totalAmount * elapsedTime) / schedule.duration;
        return vestedAmount - schedule.releasedAmount;
    }

    function getVestingSchedule(address beneficiary) external view returns (
        uint256 totalAmount,
        uint256 releasedAmount,
        uint256 startTime,
        uint256 duration,
        uint256 cliff,
        bool isActive
    ) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        return (
            schedule.totalAmount,
            schedule.releasedAmount,
            schedule.startTime,
            schedule.duration,
            schedule.cliff,
            schedule.isActive
        );
    }

    // Bridge structures
    struct BridgeRequest {
        address user;
        uint256 amount;
        uint256 timestamp;
        bool isProcessed;
    }

    // Bridge variables
    mapping(bytes32 => BridgeRequest) public bridgeRequests;
    mapping(uint256 => address) public supportedChains;
    uint256 public chainId;
    uint256 public constant BRIDGE_FEE = 100; // 1%

    // Bridge events
    event BridgeRequestCreated(
        bytes32 indexed requestId,
        address indexed user,
        uint256 amount,
        uint256 targetChain
    );
    event BridgeRequestProcessed(
        bytes32 indexed requestId,
        address indexed user,
        uint256 amount
    );

    // Bridge functions
    function setSupportedChain(uint256 _chainId, address _bridgeContract) external onlyOwner {
        require(_chainId != 0, "Invalid chain ID");
        require(_bridgeContract != address(0), "Invalid bridge contract");
        supportedChains[_chainId] = _bridgeContract;
    }

    function createBridgeRequest(uint256 amount, uint256 targetChain) external nonReentrant {
        require(amount > 0, "Amount must be positive");
        require(supportedChains[targetChain] != address(0), "Unsupported chain");
        require(targetChain != chainId, "Cannot bridge to same chain");

        uint256 fee = (amount * BRIDGE_FEE) / 10000;
        uint256 amountAfterFee = amount - fee;

        token.safeTransferFrom(msg.sender, address(this), amount);
        if (fee > 0) {
            token.safeTransfer(owner(), fee); // Use owner() as fee collector
        }

        bytes32 requestId = keccak256(
            abi.encodePacked(
                msg.sender,
                amountAfterFee,
                block.timestamp,
                targetChain
            )
        );

        bridgeRequests[requestId] = BridgeRequest({
            user: msg.sender,
            amount: amountAfterFee,
            timestamp: block.timestamp,
            isProcessed: false
        });

        emit BridgeRequestCreated(requestId, msg.sender, amountAfterFee, targetChain);
    }

    function processBridgeRequest(
        bytes32 requestId,
        address user,
        uint256 amount,
        uint256 sourceChain
    ) external onlyOwner {
        require(supportedChains[sourceChain] != address(0), "Unsupported chain");
        require(!bridgeRequests[requestId].isProcessed, "Request already processed");

        BridgeRequest storage request = bridgeRequests[requestId];
        request.isProcessed = true;

        token.safeTransfer(user, amount);
        emit BridgeRequestProcessed(requestId, user, amount);
    }

    function getBridgeRequest(bytes32 requestId) external view returns (
        address user,
        uint256 amount,
        uint256 timestamp,
        bool isProcessed
    ) {
        BridgeRequest storage request = bridgeRequests[requestId];
        return (request.user, request.amount, request.timestamp, request.isProcessed);
    }

    // Migration structures
    struct MigrationInfo {
        address oldToken;
        uint256 migrationRate;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
    }

    // Migration variables
    MigrationInfo public migrationInfo;
    mapping(address => uint256) public migratedAmounts;
    uint256 public totalMigrated;

    // Migration events
    event MigrationStarted(
        address indexed oldToken,
        uint256 migrationRate,
        uint256 startTime,
        uint256 endTime
    );
    event TokensMigrated(
        address indexed user,
        uint256 oldAmount,
        uint256 newAmount
    );

    // Migration functions
    function startMigration(
        address _oldToken,
        uint256 _migrationRate,
        uint256 _duration
    ) external onlyOwner {
        require(_oldToken != address(0), "Invalid old token");
        require(_migrationRate > 0, "Invalid migration rate");
        require(_duration > 0, "Invalid duration");
        require(!migrationInfo.isActive, "Migration already active");

        migrationInfo = MigrationInfo({
            oldToken: _oldToken,
            migrationRate: _migrationRate,
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            isActive: true
        });

        emit MigrationStarted(_oldToken, _migrationRate, block.timestamp, block.timestamp + _duration);
    }

    function migrateTokens(uint256 amount) external nonReentrant {
        require(migrationInfo.isActive, "Migration not active");
        require(block.timestamp >= migrationInfo.startTime, "Migration not started");
        require(block.timestamp <= migrationInfo.endTime, "Migration ended");
        require(amount > 0, "Amount must be positive");

        uint256 newAmount = amount * migrationInfo.migrationRate;
        require(newAmount > 0, "Invalid new amount");

        IERC20(migrationInfo.oldToken).safeTransferFrom(msg.sender, address(this), amount);
        token.safeTransfer(msg.sender, newAmount);

        migratedAmounts[msg.sender] += amount;
        totalMigrated += amount;

        emit TokensMigrated(msg.sender, amount, newAmount);
    }

    function getMigrationInfo() external view returns (
        address oldToken,
        uint256 migrationRate,
        uint256 startTime,
        uint256 endTime,
        bool isActive
    ) {
        return (
            migrationInfo.oldToken,
            migrationInfo.migrationRate,
            migrationInfo.startTime,
            migrationInfo.endTime,
            migrationInfo.isActive
        );
    }

    function getUserMigrationInfo(address user) external view returns (uint256) {
        return migratedAmounts[user];
    }

    // Token Analytics structures
    struct TokenStats {
        uint256 totalTransactions;
        uint256 totalVolume;
    }

    // Token Analytics variables
    TokenStats public tokenStats;

    // Token Analytics functions
    function getTokenStats() external view returns (
        uint256 totalTransactions,
        uint256 totalVolume
    ) {
        return (
            tokenStats.totalTransactions,
            tokenStats.totalVolume
        );
    }

    // Token Metadata structures
    struct TokenMetadata {
        string name;
        string symbol;
        uint8 decimals;
    }

    // Token Metadata variables
    TokenMetadata public tokenMetadata;

    // Token Metadata events
    event MetadataUpdated(
        string name,
        string symbol,
        uint8 decimals
    );

    // Token Metadata functions
    function setTokenMetadata(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) external onlyOwner {
        tokenMetadata = TokenMetadata({
            name: _name,
            symbol: _symbol,
            decimals: _decimals
        });

        emit MetadataUpdated(_name, _symbol, _decimals);
    }

    function getTokenMetadata() external view returns (
        string memory name,
        string memory symbol,
        uint8 decimals
    ) {
        return (
            tokenMetadata.name,
            tokenMetadata.symbol,
            tokenMetadata.decimals
        );
    } 
    
    // Monad Dev Mission: Keep Building...
    
} 
