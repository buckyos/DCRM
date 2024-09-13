// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./dividend.sol";

import "hardhat/console.sol";

contract ProposalContract is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    DividendContract dividendContract;

    struct VoteInfo {
        address voter;
        bool support;
        uint256 amount;
        string desc;
        uint256 timestamp;
    }

    enum ProposalType {
        Normal,
        Transfer
    }

    struct Proposal {
        string title;
        string desc;
        uint256 endtime;
        uint256 totalSupport;
        uint256 totalOppose;
        uint256 minValidAmount;
        ProposalType proposaltype;
        bytes32 paramHash;
        address proposer;
        bool executed;
        mapping (address => bool) voted;
        VoteInfo[] votes;
    }

    struct ProposalBrief {
        string title;
        string desc;
        uint256 endtime;
        uint256 totalSupport;
        uint256 totalOppose;
        uint256 totalVotes;
        uint256 minValidAmount;
        ProposalType proposaltype;
    }

    mapping (uint256 => Proposal) public proposals;
    uint256 curProposalId;
    uint256 maxDuration;
    uint256 minStack;

    event CreateProposal(uint256 id);
    event Vote(uint256 indexed id, address indexed voter, bool support, uint256 amount, string desc);
    // executed == true代表执行，false代表取消
    event ExecuteProposal(uint256 id, bool executed);

    function initialize(address dividendAddress, uint256 _maxDuration, uint256 _minStack) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);

        dividendContract = DividendContract(payable(dividendAddress));
        maxDuration = _maxDuration;
        minStack = _minStack;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function createNormalProposal(string calldata _title, string calldata desc, uint256 duration) public {
        _createProposal(_title, desc, duration, 0, ProposalType.Normal, bytes32(0));
    }

    function _createProposal(string calldata _title, string calldata desc, uint256 duration, uint256 minValidAmount, ProposalType _type, bytes32 proposalParamHash) internal {
        require(duration <= maxDuration, "Duration too long");
        uint256 lockedAmount = dividendContract.updateLockState(msg.sender);
        require(lockedAmount >= minStack, "Locked amount not enough");
        uint256 proposalId = ++curProposalId;

        proposals[proposalId].title = _title;
        proposals[proposalId].desc = desc;
        proposals[proposalId].endtime = block.timestamp + duration;
        proposals[proposalId].minValidAmount = minValidAmount;
        proposals[proposalId].proposaltype = _type;
        proposals[proposalId].paramHash = proposalParamHash;
        proposals[proposalId].proposer = msg.sender;

        emit CreateProposal(proposalId);
    }

    function supportProposal(uint256 id, string calldata desc) public {
        require(proposals[id].endtime != 0, "Proposal not exist");
        require(proposals[id].endtime > block.timestamp, "Proposal ended");
        require(proposals[id].voted[msg.sender] == false, "Already voted");

        uint256 lockedAmount = dividendContract.updateLockState(msg.sender);
        if (lockedAmount == 0) {
            return;
        }
        proposals[id].totalSupport += lockedAmount;
        proposals[id].voted[msg.sender] = true;
        proposals[id].votes.push(VoteInfo(msg.sender, true, lockedAmount, desc, block.timestamp));

        emit Vote(id, msg.sender, true, lockedAmount, desc);
    }

    function opposeProposal(uint256 id, string calldata desc) public {
        require(proposals[id].endtime != 0, "Proposal not exist");
        require(proposals[id].endtime > block.timestamp, "Proposal ended");
        require(proposals[id].voted[msg.sender] == false, "Already voted");

        uint256 lockedAmount = dividendContract.updateLockState(msg.sender);
        if (lockedAmount == 0) {
            return;
        }
        proposals[id].totalOppose += lockedAmount;
        proposals[id].voted[msg.sender] = true;
        proposals[id].votes.push(VoteInfo(msg.sender, false, lockedAmount, desc, block.timestamp));

        emit Vote(id, msg.sender, false, lockedAmount, desc);
    }

    function getProposal(uint256 id) public view returns (ProposalBrief memory) {
        Proposal storage proposal = proposals[id];
        ProposalBrief memory brief;
        brief.title = proposal.title;
        brief.desc = proposal.desc;
        brief.endtime = proposal.endtime;
        brief.totalSupport = proposal.totalSupport;
        brief.totalOppose = proposal.totalOppose;
        brief.totalVotes = proposal.votes.length;
        brief.minValidAmount = proposal.minValidAmount;
        brief.proposaltype = proposal.proposaltype;

        return brief;
    }

    function getProposalVotes(uint256 id, uint256 page, uint256 size) public view returns (VoteInfo[] memory) {
        Proposal storage proposal = proposals[id];
        uint256 start = page * size;
        uint256 end = (page + 1) * size;
        if (end > proposal.votes.length) {
            end = proposal.votes.length;
        }
        VoteInfo[] memory votes = new VoteInfo[](end - start);
        for (uint256 i = start; i < end; i++) {
            votes[i - start] = proposal.votes[i];
        }
        return votes;
    }

    function getProposalCount() view public returns (uint256) {
        return curProposalId;
    }

    // 作为示例，实现一个转账提案，提案内容为：发起者将amount数量的token转给to，提案同意则转账，不同意则退还给发起者
    function createTransferProposal(string calldata _title, string calldata desc, uint256 duration, uint256 minValidAmount, address token, uint256 amount, address to) public {
        bytes32 paramHash = keccak256(abi.encodePacked(token, amount, to));
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _createProposal(_title, desc, duration, minValidAmount, ProposalType.Transfer, paramHash);
    }

    function executeTransferProposal(uint256 id, address token, uint256 amount, address to) public {
        require(proposals[id].endtime != 0, "Proposal not exist");
        require(proposals[id].proposaltype == ProposalType.Transfer, "Not transfer proposal");
        require(proposals[id].endtime < block.timestamp, "Proposal not ended");
        require(proposals[id].minValidAmount >= proposals[id].totalSupport + proposals[id].totalOppose, "Not enough votes");
        require(proposals[id].totalSupport > proposals[id].totalOppose, "Proposal not passed");
        require(proposals[id].paramHash == keccak256(abi.encodePacked(token, amount, to)), "Invalid param hash");
        require(proposals[id].executed == false, "Proposal executed");
        

        proposals[id].executed = true;

        IERC20(token).transfer(to, amount);

        emit ExecuteProposal(id, true);
    }

    function cancelTransferProposal(uint256 id, address token, uint256 amount, address to) public {
        require(proposals[id].endtime != 0, "Proposal not exist");
        require(proposals[id].proposaltype == ProposalType.Transfer, "Not transfer proposal");
        require(proposals[id].endtime < block.timestamp, "Proposal not ended");
        require(proposals[id].totalSupport <= proposals[id].totalOppose, "Proposal passed");
        require(proposals[id].paramHash == keccak256(abi.encodePacked(token, amount, to)), "Invalid param hash");
        require(proposals[id].executed == false, "Proposal executed");

        proposals[id].executed = true;

        IERC20(token).transfer(proposals[id].proposer, amount);

        emit ExecuteProposal(id, false);
    }
}