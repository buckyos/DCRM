// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./dividend.sol";

import "hardhat/console.sol";

contract ProposalContract is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    DividendContract dividendContract;

    struct VoteInfo {
        address voter;
        bool support;
        uint256 amount;
        string desc;
    }
    struct Proposal {
        string title;
        string desc;
        uint256 endtime;
        uint256 totalSupport;
        uint256 totalOppose;
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
    }

    mapping (uint256 => Proposal) public proposals;
    uint256 curProposalId;

    event CreateProposal(uint256 id);
    event Vote(uint256 indexed id, address indexed voter, bool support, uint256 amount, string desc);

    function initialize(address dividendAddress) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);

        dividendContract = DividendContract(payable(dividendAddress));
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function createProposal(string calldata _title, string calldata desc, uint256 duration) public {
        require(duration <= 3 days, "Duration too long");
        uint256 lockedAmount = dividendContract.updateLockState(msg.sender);
        require(lockedAmount >= 50000 ether, "Locked amount not enough");
        uint256 proposalId = ++curProposalId;

        proposals[proposalId].title = _title;
        proposals[proposalId].desc = desc;
        proposals[proposalId].endtime = block.timestamp + duration;

        emit CreateProposal(proposalId);
    }

    function supportProposal(uint256 id, string calldata desc) public {
        require(proposals[id].endtime > block.timestamp, "Proposal ended");
        require(proposals[id].voted[msg.sender] == false, "Already voted");

        uint256 lockedAmount = dividendContract.updateLockState(msg.sender);
        if (lockedAmount == 0) {
            return;
        }
        proposals[id].totalSupport += lockedAmount;
        proposals[id].voted[msg.sender] = true;
        proposals[id].votes.push(VoteInfo(msg.sender, true, lockedAmount, desc));

        emit Vote(id, msg.sender, true, lockedAmount, desc);
    }

    function opposeProposal(uint256 id, string calldata desc) public {
        require(proposals[id].endtime > block.timestamp, "Proposal ended");
        require(proposals[id].voted[msg.sender] == false, "Already voted");

        uint256 lockedAmount = dividendContract.updateLockState(msg.sender);
        if (lockedAmount == 0) {
            return;
        }
        proposals[id].totalOppose += lockedAmount;
        proposals[id].voted[msg.sender] = true;
        proposals[id].votes.push(VoteInfo(msg.sender, false, lockedAmount, desc));

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
}