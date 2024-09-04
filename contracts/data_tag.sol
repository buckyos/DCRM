
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

contract DataTag is Ownable {
    struct Tag {
        string name;
        string desc;
        bytes32 parent;
        bytes32[] children; 
    }

    mapping(bytes32 => Tag) public tags;    // 由name的hash做key

    struct DataTagInfo {
        bool valid;                         // valid为true，表示数据有这个tag。因为solidity的map始终返回值
        uint128 like;
        uint128 dislike;
        mapping(address => int8) userlike;  // 1代表赞，0代表不点，-1代表否
    }

    struct Data {
        bytes32[] tags;
        mapping(bytes32 => DataTagInfo) tag_info;    // 每个TAG的赞否数据，一个账户只能点一次赞或否
    }

    mapping(bytes32 => Data) datas;

    event TagCreated(bytes32 tagHash, bytes32 tagParent, string name);
    event AddDataTag(bytes32 dataHash, bytes32 tag);
    event RateDataTag(address rater, bytes32 dataHash, bytes32 tag, int8 like);

    constructor() Ownable(msg.sender) {}

    function createTag(string[] calldata new_tags, string[] calldata descs) onlyOwner public {
        bytes32 parent = bytes32(0);
        for (uint i = 0; i < new_tags.length; i++) {
            bytes32 tagHash = keccak256(abi.encodePacked(new_tags[i]));
            if (bytes(tags[tagHash].name).length != 0) {
                parent = tagHash;
                continue;
            }

            tags[tagHash] = Tag(new_tags[i], descs[i], parent, new bytes32[](0));

            if (parent != bytes32(0)) {
                tags[parent].children.push(tagHash);
            }

            emit TagCreated(tagHash, parent, new_tags[i]);
            parent = tagHash;
        }
    }

    function modifyTagDesc(string calldata tag, string calldata desc) onlyOwner public {
        bytes32 tagHash = keccak256(abi.encodePacked(tag));
        require(bytes(tags[tagHash].name).length != 0, "tag not exist");
        tags[tagHash].desc = desc;
    }

    // 添加同时也等于点赞
    function addDataTag(bytes32 dataHash, string[] calldata data_tags) public {
        for (uint i = 0; i < data_tags.length; i++) {
            bytes32 tagHash = keccak256(abi.encodePacked(data_tags[i]));
            if (!datas[dataHash].tag_info[tagHash].valid) {
                datas[dataHash].tags.push(tagHash);
                datas[dataHash].tag_info[tagHash].valid = true;
                emit AddDataTag(dataHash, tagHash);
            }

            _ratingDataTag(dataHash, tagHash, 1);
        }
    }

    function ratingDataTag(bytes32 dataHash, string calldata tag, int8 like) public {
        bytes32 tagHash = keccak256(abi.encodePacked(tag));
        require(datas[dataHash].tag_info[tagHash].valid, "tag not exist");

        _ratingDataTag(dataHash, tagHash, like);
    }

    function _ratingDataTag(bytes32 dataHash, bytes32 tagHash, int8 like) internal {
        int8 oldRating = datas[dataHash].tag_info[tagHash].userlike[msg.sender];
        if (oldRating == like) {
            return;
        }

        datas[dataHash].tag_info[tagHash].userlike[msg.sender] = like;

        if (oldRating == 1) {
            datas[dataHash].tag_info[tagHash].like--;
        } else if (oldRating == -1) {
            datas[dataHash].tag_info[tagHash].dislike--;
        }

        if (like == 1) {
            datas[dataHash].tag_info[tagHash].like++;
        } else {
            datas[dataHash].tag_info[tagHash].dislike++;
        }
        emit RateDataTag(msg.sender, dataHash, tagHash, like);
    }
}