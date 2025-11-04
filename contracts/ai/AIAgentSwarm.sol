// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title AIAgentSwarm
 * @notice Decentralized AI agent swarm for institutional finance automation
 * @dev Coordinates multiple AI agents for compliance, risk, trading, and governance
 */
contract AIAgentSwarm is Ownable, ReentrancyGuard {

    enum AgentType {
        COMPLIANCE_MONITOR,
        RISK_ASSESSOR,
        YIELD_OPTIMIZER,
        MARKET_MAKER,
        GOVERNANCE_AGENT,
        LIQUIDITY_PROVIDER,
        ARBITRAGE_BOT,
        PORTFOLIO_MANAGER,
        COMPLIANCE_REPORTER,
        REGULATORY_WATCHDOG,
        TREASURY_MANAGER,
        CREDIT_SCORER,
        FRAUD_DETECTOR,
        MARKET_ANALYST,
        SETTLEMENT_COORDINATOR
    }

    enum AgentStatus {
        INACTIVE,
        ACTIVE,
        SUSPENDED,
        MAINTENANCE,
        DEPRECATED
    }

    enum TaskPriority {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }

    struct AIAgent {
        bytes32 agentId;
        string agentName;
        AgentType agentType;
        address agentAddress;
        address operator;
        AgentStatus status;
        uint256 trustScore;
        uint256 lastActivity;
        uint256 totalTasksExecuted;
        uint256 successRate; // BPS
        bytes32[] capabilities;
        mapping(bytes32 => uint256) performanceMetrics;
        mapping(bytes32 => bool) permissions;
    }

    struct Task {
        bytes32 taskId;
        bytes32 agentId;
        string taskDescription;
        TaskPriority priority;
        uint256 deadline;
        uint256 reward;
        address requester;
        bool isCompleted;
        bytes result;
        uint256 executionTime;
    }

    struct SwarmIntelligence {
        bytes32 intelligenceId;
        string topic;
        bytes32[] contributingAgents;
        bytes aggregatedData;
        uint256 confidenceScore;
        uint256 lastUpdate;
        bool isActive;
    }

    // Storage
    mapping(bytes32 => AIAgent) public aiAgents;
    mapping(bytes32 => Task) public tasks;
    mapping(bytes32 => SwarmIntelligence) public swarmIntelligence;
    mapping(AgentType => bytes32[]) public agentsByType;
    mapping(address => bytes32[]) public operatorAgents;
    mapping(bytes32 => bytes32[]) public agentTasks;

    // Global statistics
    uint256 public totalAgents;
    uint256 public totalTasks;
    uint256 public activeTasks;
    uint256 public completedTasks;

    // Swarm parameters
    uint256 public minTrustScore = 500; // Minimum trust score to operate
    uint256 public maxConcurrentTasks = 100; // Max tasks per agent
    uint256 public taskTimeout = 1 hours; // Task execution timeout
    uint256 public swarmConsensusThreshold = 7000; // 70% consensus required

    // Events
    event AgentRegistered(bytes32 indexed agentId, string agentName, AgentType agentType);
    event TaskAssigned(bytes32 indexed taskId, bytes32 indexed agentId, TaskPriority priority);
    event TaskCompleted(bytes32 indexed taskId, bool success, uint256 executionTime);
    event SwarmIntelligenceUpdated(bytes32 indexed intelligenceId, uint256 confidenceScore);
    event AgentStatusChanged(bytes32 indexed agentId, AgentStatus newStatus);

    modifier validAgent(bytes32 _agentId) {
        require(aiAgents[_agentId].agentAddress != address(0), "Agent not found");
        _;
    }

    modifier onlyAgentOperator(bytes32 _agentId) {
        require(aiAgents[_agentId].operator == msg.sender || owner() == msg.sender, "Not agent operator");
        _;
    }

    modifier agentActive(bytes32 _agentId) {
        require(aiAgents[_agentId].status == AgentStatus.ACTIVE, "Agent not active");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new AI agent in the swarm
     */
    function registerAIAgent(
        string memory _agentName,
        AgentType _agentType,
        address _agentAddress,
        bytes32[] memory _capabilities
    ) external returns (bytes32) {
        require(_agentAddress != address(0), "Invalid agent address");
        require(bytes(_agentName).length > 0, "Invalid agent name");

        bytes32 agentId = keccak256(abi.encodePacked(
            _agentName,
            _agentType,
            _agentAddress,
            block.timestamp
        ));

        require(aiAgents[agentId].agentAddress == address(0), "Agent already exists");

        AIAgent storage agent = aiAgents[agentId];
        agent.agentId = agentId;
        agent.agentName = _agentName;
        agent.agentType = _agentType;
        agent.agentAddress = _agentAddress;
        agent.operator = msg.sender;
        agent.status = AgentStatus.ACTIVE;
        agent.trustScore = 500; // Base trust score
        agent.lastActivity = block.timestamp;
        agent.capabilities = _capabilities;

        // Grant basic permissions
        agent.permissions[keccak256("EXECUTE_TASKS")] = true;
        agent.permissions[keccak256("REPORT_METRICS")] = true;

        agentsByType[_agentType].push(agentId);
        operatorAgents[msg.sender].push(agentId);
        totalAgents++;

        emit AgentRegistered(agentId, _agentName, _agentType);
        return agentId;
    }

    /**
     * @notice Assign a task to an AI agent
     */
    function assignTask(
        bytes32 _agentId,
        string memory _taskDescription,
        TaskPriority _priority,
        uint256 _deadline,
        uint256 _reward
    ) external payable validAgent(_agentId) agentActive(_agentId) returns (bytes32) {
        require(msg.value >= _reward, "Insufficient reward payment");
        require(_deadline > block.timestamp, "Invalid deadline");

        AIAgent storage agent = aiAgents[_agentId];
        require(agentTasks[_agentId].length < maxConcurrentTasks, "Agent at max capacity");

        bytes32 taskId = keccak256(abi.encodePacked(
            _agentId,
            _taskDescription,
            block.timestamp
        ));

        Task storage task = tasks[taskId];
        task.taskId = taskId;
        task.agentId = _agentId;
        task.taskDescription = _taskDescription;
        task.priority = _priority;
        task.deadline = _deadline;
        task.reward = _reward;
        task.requester = msg.sender;

        agentTasks[_agentId].push(taskId);
        activeTasks++;

        emit TaskAssigned(taskId, _agentId, _priority);
        return taskId;
    }

    /**
     * @notice Complete a task (called by agent)
     */
    function completeTask(
        bytes32 _taskId,
        bool _success,
        bytes memory _result
    ) external validAgent(tasks[_taskId].agentId) {
        Task storage task = tasks[_taskId];
        require(task.agentId == keccak256(abi.encodePacked(msg.sender)), "Not assigned agent");
        require(!task.isCompleted, "Task already completed");
        require(block.timestamp <= task.deadline, "Task deadline exceeded");

        task.isCompleted = true;
        task.result = _result;
        task.executionTime = block.timestamp - task.lastActivity;

        AIAgent storage agent = aiAgents[task.agentId];
        agent.lastActivity = block.timestamp;
        agent.totalTasksExecuted++;

        // Update success rate
        if (_success) {
            agent.successRate = ((agent.successRate * (agent.totalTasksExecuted - 1)) + 10000) / agent.totalTasksExecuted;
            agent.trustScore = agent.trustScore + 10 > 1000 ? 1000 : agent.trustScore + 10;
        } else {
            agent.successRate = ((agent.successRate * (agent.totalTasksExecuted - 1))) / agent.totalTasksExecuted;
            agent.trustScore = agent.trustScore > 50 ? agent.trustScore - 50 : 0;
        }

        // Pay reward
        payable(agent.operator).transfer(task.reward);

        activeTasks--;
        completedTasks++;

        emit TaskCompleted(_taskId, _success, task.executionTime);
    }

    /**
     * @notice Create swarm intelligence from multiple agents
     */
    function createSwarmIntelligence(
        string memory _topic,
        bytes32[] memory _contributingAgents,
        bytes memory _aggregatedData
    ) external onlyOwner returns (bytes32) {
        require(_contributingAgents.length > 0, "No contributing agents");

        bytes32 intelligenceId = keccak256(abi.encodePacked(
            _topic,
            _contributingAgents,
            block.timestamp
        ));

        SwarmIntelligence storage intelligence = swarmIntelligence[intelligenceId];
        intelligence.intelligenceId = intelligenceId;
        intelligence.topic = _topic;
        intelligence.contributingAgents = _contributingAgents;
        intelligence.aggregatedData = _aggregatedData;
        intelligence.confidenceScore = 5000; // Base confidence
        intelligence.lastUpdate = block.timestamp;
        intelligence.isActive = true;

        emit SwarmIntelligenceUpdated(intelligenceId, intelligence.confidenceScore);
        return intelligenceId;
    }

    /**
     * @notice Update agent permissions
     */
    function updateAgentPermissions(
        bytes32 _agentId,
        bytes32 _permission,
        bool _granted
    ) external onlyAgentOperator(_agentId) {
        aiAgents[_agentId].permissions[_permission] = _granted;
    }

    /**
     * @notice Update agent status
     */
    function updateAgentStatus(
        bytes32 _agentId,
        AgentStatus _newStatus
    ) external onlyAgentOperator(_agentId) {
        aiAgents[_agentId].status = _newStatus;
        emit AgentStatusChanged(_agentId, _newStatus);
    }

    /**
     * @notice Report agent performance metrics
     */
    function reportPerformanceMetrics(
        bytes32 _agentId,
        bytes32 _metricType,
        uint256 _value
    ) external {
        AIAgent storage agent = aiAgents[_agentId];
        require(agent.agentAddress == msg.sender || agent.operator == msg.sender, "Not authorized");

        agent.performanceMetrics[_metricType] = _value;
        agent.lastActivity = block.timestamp;
    }

    /**
     * @notice Get agent details
     */
    function getAIAgent(bytes32 _agentId)
        external
        view
        returns (
            string memory agentName,
            AgentType agentType,
            address agentAddress,
            AgentStatus status,
            uint256 trustScore,
            uint256 successRate
        )
    {
        AIAgent memory agent = aiAgents[_agentId];
        return (
            agent.agentName,
            agent.agentType,
            agent.agentAddress,
            agent.status,
            agent.trustScore,
            agent.successRate
        );
    }

    /**
     * @notice Get task details
     */
    function getTask(bytes32 _taskId)
        external
        view
        returns (
            bytes32 agentId,
            string memory taskDescription,
            TaskPriority priority,
            bool isCompleted,
            bytes memory result
        )
    {
        Task memory task = tasks[_taskId];
        return (
            task.agentId,
            task.taskDescription,
            task.priority,
            task.isCompleted,
            task.result
        );
    }

    /**
     * @notice Get agents by type
     */
    function getAgentsByType(AgentType _type)
        external
        view
        returns (bytes32[] memory)
    {
        return agentsByType[_type];
    }

    /**
     * @notice Get agent tasks
     */
    function getAgentTasks(bytes32 _agentId)
        external
        view
        returns (bytes32[] memory)
    {
        return agentTasks[_agentId];
    }

    /**
     * @notice Check agent permission
     */
    function checkAgentPermission(bytes32 _agentId, bytes32 _permission)
        external
        view
        returns (bool)
    {
        return aiAgents[_agentId].permissions[_permission];
    }

    /**
     * @notice Get swarm intelligence
     */
    function getSwarmIntelligence(bytes32 _intelligenceId)
        external
        view
        returns (
            string memory topic,
            uint256 confidenceScore,
            uint256 lastUpdate,
            bool isActive
        )
    {
        SwarmIntelligence memory intelligence = swarmIntelligence[_intelligenceId];
        return (
            intelligence.topic,
            intelligence.confidenceScore,
            intelligence.lastUpdate,
            intelligence.isActive
        );
    }

    /**
     * @notice Update swarm parameters
     */
    function updateSwarmParameters(
        uint256 _minTrustScore,
        uint256 _maxConcurrentTasks,
        uint256 _taskTimeout,
        uint256 _swarmConsensusThreshold
    ) external onlyOwner {
        minTrustScore = _minTrustScore;
        maxConcurrentTasks = _maxConcurrentTasks;
        taskTimeout = _taskTimeout;
        swarmConsensusThreshold = _swarmConsensusThreshold;
    }

    /**
     * @notice Emergency suspend agent
     */
    function emergencySuspendAgent(bytes32 _agentId) external onlyOwner {
        aiAgents[_agentId].status = AgentStatus.SUSPENDED;
        emit AgentStatusChanged(_agentId, AgentStatus.SUSPENDED);
    }

    /**
     * @notice Get global statistics
     */
    function getGlobalStatistics()
        external
        view
        returns (
            uint256 _totalAgents,
            uint256 _totalTasks,
            uint256 _activeTasks,
            uint256 _completedTasks
        )
    {
        return (totalAgents, totalTasks, activeTasks, completedTasks);
    }
}
