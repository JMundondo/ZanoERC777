// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


// ZANO Stablecoin Token Contract
contract ZANOToken is ERC777, Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(
        address[] memory defaultOperators
    ) ERC777("ZANO Stablecoin", "ZANO", defaultOperators) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MINTER_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
    }

    function mint(address account, uint256 amount, bytes memory userData, bytes memory operatorData)
        public
        onlyRole(MINTER_ROLE)
    {
        _mint(account, amount, userData, operatorData);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256 amount
    ) internal virtual override whenNotPaused {
        super._beforeTokenTransfer(operator, from, to, amount);
    }
}

// ICO Contract for ZANO Token
contract ZANOICO is ReentrancyGuard, AccessControl {
    using SafeMath for uint256;

    ZANOToken public token;
    address payable public treasury;
    
    uint256 public price = 1 ether; // 1 ZANO = 1 ETH initially
    uint256 public minPurchase = 0.1 ether;
    uint256 public maxPurchase = 100 ether;
    
    uint256 public startTime;
    uint256 public endTime;
    uint256 public hardCap;
    uint256 public totalRaised;

    bool public isFinalized = false;

    event TokensPurchased(address indexed purchaser, uint256 amount, uint256 tokens);
    event ICOFinalized(uint256 totalRaised);

    constructor(
        address _tokenAddress,
        address payable _treasury,
        uint256 _startTime,
        uint256 _duration,
        uint256 _hardCap
    ) {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        require(_treasury != address(0), "Treasury address cannot be zero");
        
        token = ZANOToken(_tokenAddress);
        treasury = _treasury;
        startTime = _startTime;
        endTime = _startTime.add(_duration);
        hardCap = _hardCap;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function buyTokens() external payable nonReentrant {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "ICO is not active");
        require(!isFinalized, "ICO has been finalized");
        require(msg.value >= minPurchase, "Below minimum purchase amount");
        require(msg.value <= maxPurchase, "Exceeds maximum purchase amount");
        require(totalRaised.add(msg.value) <= hardCap, "Hard cap reached");

        uint256 tokens = calculateTokenAmount(msg.value);
        totalRaised = totalRaised.add(msg.value);

        // Transfer tokens to buyer
        token.mint(msg.sender, tokens, "", "");
        
        // Transfer ETH to treasury
        treasury.transfer(msg.value);

        emit TokensPurchased(msg.sender, msg.value, tokens);
    }

    function calculateTokenAmount(uint256 weiAmount) public view returns (uint256) {
        return weiAmount.mul(1e18).div(price);
    }

    function finalize() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(block.timestamp > endTime || totalRaised >= hardCap, "ICO not ended");
        require(!isFinalized, "ICO already finalized");

        isFinalized = true;
        emit ICOFinalized(totalRaised);
    }
}

// Governance Contract for ZANO
contract ZANOGovernance is AccessControl {
    using SafeMath for uint256;

    struct Proposal {
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    ZANOToken public token;
    uint256 public proposalCount;
    uint256 public votingPeriod = 3 days;
    uint256 public quorum = 100000 * 1e18; // 100,000 ZANO tokens required for quorum

    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(uint256 indexed proposalId, string description, uint256 startTime, uint256 endTime);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        token = ZANOToken(_tokenAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createProposal(string memory description) external {
        require(token.balanceOf(msg.sender) >= 10000 * 1e18, "Must hold at least 10,000 ZANO tokens to create proposal");
        
        proposalCount++;
        Proposal storage proposal = proposals[proposalCount];
        proposal.description = description;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp.add(votingPeriod);
        
        emit ProposalCreated(proposalCount, description, proposal.startTime, proposal.endTime);
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        
        uint256 votes = token.balanceOf(msg.sender);
        require(votes > 0, "No voting power");

        proposal.hasVoted[msg.sender] = true;
        
        if (support) {
            proposal.forVotes = proposal.forVotes.add(votes);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(votes);
        }

        emit Voted(proposalId, msg.sender, support, votes);
    }

    function executeProposal(uint256 proposalId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting not ended");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.forVotes.add(proposal.againstVotes) >= quorum, "Quorum not reached");
        
        proposal.executed = true;
        
        emit ProposalExecuted(proposalId);
    }
}