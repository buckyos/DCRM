
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

contract DataTag is Ownable {
    // 通用的，包含赞同/反对信息的Meta数据结构。tag和data-tag都会用到这个数据结构
    struct MetaData {
        bool valid;                         // 这个字段通常用在mapping的value，用这个字段表示这个value是否为空
        string meta;                        // 元数据。在tag系统下，它是tag的描述；在data-tag系统下，它是附加这个tag的原因
        uint128 like;                       
        uint128 dislike;                    
        mapping(address => int8) userlike;  // 1代表赞，0代表不点，-1代表否
    }

    struct MetaDataOutput {
        string meta;
        uint128 like;
        uint128 dislike;
        int8 myLike;
    }

    struct Tag {
        string name;                         // 这个tag的单独名字
        bytes32 parent;                      // parent为0表示顶层TAG
        bytes32[] children;                  // 考虑一个TAG的子TAG不会很多
        mapping(address => MetaData) metas;  // 每个用户对tag的描述
        // 由于TAG可能包括很多数据，合约里不提供反向查询，靠后端扫描事件来重建数据库
    }

    // 由于mapping不能返回给外界，需要一个单独的结构体来支持view函数
    struct TagOutput {
        string fullName;      // 直接返回整个路径,由"/"分隔
        bytes32 parent;
        string[] children;
        // 因为使用哪种描述，是前/后端的逻辑，这里就不返回任何描述信息
    }

    mapping(bytes32 => Tag) tags;    // 由name的hash做key

    struct Data {
        bytes32[] tags;
        mapping(bytes32 => MetaData) tag_info;    // 每个TAG的赞否数据，一个账户只能点一次赞或否
    }

    struct DataOutput {
        bytes32[] tags;
    }

    mapping(bytes32 => Data) datas;

    // 更新tag的meta描述，首次更新相当于创建这个tag
    event TagUpdated(bytes32 indexed tagHash, address indexed from);
    // 数据的tag改变。如果是新增tag，oldTag为bytes32(0)
    // oldTag不为空，出现在父TAG被子TAG替换的情况
    event ReplaceDataTag(bytes32 indexed dataHash, bytes32 indexed oldTag, bytes32 indexed newTag);
    // 给tag的meta点赞或反对
    event RateTagMeta(bytes32 indexed tagHash, address indexed from, address indexed rater, int8 like);
    // 给数据的tag本身点赞或反对
    event RateDataTag(bytes32 indexed dataHash, bytes32 indexed tag, address indexed rater, int8 like);

    constructor() Ownable(msg.sender) {}

    function calcTagHash(string[] calldata name) pure public returns (bytes32) {
        string memory fullName = "";
        for (uint i = 0; i < name.length; i++) {
            fullName = string.concat(fullName, "/", name[i]);
        }
        return keccak256(abi.encodePacked(fullName));
    }

    /**
     * 设置一个tag的描述。设置描述也等于自己对这个描述点赞
     * @param new_tags tag的全路径，比如["a", "b", "c"]表示一个tag的全路径是a/b/c
     * @param meta 这个tag本身的meta信息。如果路径中间的某个tag不存在，这个tag的meta信息默认为空，等待后续更新
     */
    function setTagMeta(string[] calldata new_tags, string calldata meta) public {
        bytes32 parent = bytes32(0);
        string memory fullName = "";
        for (uint i = 0; i < new_tags.length; i++) {
            require(bytes(new_tags[i]).length != 0, "empty name");

            fullName = string.concat(fullName, "/", new_tags[i]);
            bytes32 tagHash = keccak256(abi.encodePacked(fullName));
            if (bytes(tags[tagHash].name).length == 0) {
                // create tag
                tags[tagHash].name = new_tags[i];
                if (parent != bytes32(0)) {
                    tags[tagHash].parent = parent;
                    tags[parent].children.push(tagHash);
                }
            }

            parent = tagHash;

            MetaData storage tagMetaData = tags[tagHash].metas[msg.sender];
            if (!tagMetaData.valid || i == new_tags.length - 1) {
                // set meta data
                string memory tagMeta = "";
                if (i == new_tags.length - 1) {
                    tagMeta = meta;
                }

                tagMetaData.meta = tagMeta;
                tagMetaData.valid = true;
                emit TagUpdated(tagHash, msg.sender);

                // 自己给自己tag的描述点赞
                _rateTagMeta(tagHash, msg.sender, 1);
            }
        }
    }

    function _rateMeta(MetaData storage meta, int8 like) internal returns (bool) {
        int8 oldRating = meta.userlike[msg.sender];
        if (oldRating == like) {
            return false;
        }

        meta.userlike[msg.sender] = like;

        if (oldRating == 1) {
            meta.like--;
        } else if (oldRating == -1) {
            meta.dislike--;
        }

        if (like == 1) {
            meta.like++;
        } else if (like == -1) {
            meta.dislike++;
        }

        return true;
    }

    function _rateTagMeta(bytes32 tagHash, address from, int8 like) internal {
        MetaData storage meta = tags[tagHash].metas[from];
        
        if (_rateMeta(meta, like)) {
            emit RateTagMeta(tagHash, from, msg.sender, like);
        }
    }

    function rateTagMeta(bytes32 tagHash, address from, int8 like) public {
        require(tags[tagHash].metas[from].valid, "meta not exist");
        _rateTagMeta(tagHash, from, like);
    }

    /**
     * 给数据附加tag。可以一次性附加多个, 先实现成tag必须存在才能附加
     * @param dataHash 数据的hash
     * @param data_tags 要附加的全部tagHash
     */
    // TODO: 不允许同时存在父TAG和子TAG。在存在父TAG的情况下，再设置子TAG，父TAG会被替换成子TAG
    function addDataTag(bytes32 dataHash, bytes32[] calldata data_tags, string[] calldata data_tag_metas) public {
        require(data_tags.length == data_tag_metas.length, "invalid input");

        for (uint i = 0; i < data_tags.length; i++) {
            bytes32 tagHash = data_tags[i];
            require(bytes(tags[tagHash].name).length != 0, "tag not exist");
            
            MetaData storage dataTagMeta = datas[dataHash].tag_info[tagHash];

            if (!dataTagMeta.valid) {
                datas[dataHash].tags.push(tagHash);
                dataTagMeta.valid = true;
                dataTagMeta.meta = data_tag_metas[i];
                emit ReplaceDataTag(dataHash, bytes32(0), tagHash);
            }

            _rateDataTag(dataHash, tagHash, 1);
        }
    }

    /**
     * 评价数据的tag本身
     * @param dataHash 数据的dataHash
     * @param tagHash tag的hash
     * @param like 1代表赞同，-1代表反对，0代表取消之前的评价
     */
    function rateDataTag(bytes32 dataHash, bytes32 tagHash, int8 like) public {
        require(datas[dataHash].tag_info[tagHash].valid, "tag not exist");

        _rateDataTag(dataHash, tagHash, like);
    }

    function _rateDataTag(bytes32 dataHash, bytes32 tagHash, int8 like) internal {
        MetaData storage dataTagMeta = datas[dataHash].tag_info[tagHash];
        if (_rateMeta(dataTagMeta, like)) {
            emit RateDataTag(dataHash, tagHash, msg.sender, like);
        }
    }

    function getTagName(bytes32 tagHash) public view returns (string memory) {
        return tags[tagHash].name;
    }

    function getTagInfo(bytes32 tagHash) public view returns (TagOutput memory) {
        string memory fullName = tags[tagHash].name;
        bytes32 parent = tags[tagHash].parent;
        while (parent != bytes32(0)) {
            fullName = string.concat(tags[parent].name, "/", fullName);
            parent = tags[parent].parent;
        }

        fullName = string.concat("/", fullName);

        string[] memory childrenNames = new string[](tags[tagHash].children.length);
        for (uint i = 0; i < tags[tagHash].children.length; i++) {
            childrenNames[i] = getTagName(tags[tagHash].children[i]);
        }

        return TagOutput(fullName, tags[tagHash].parent, childrenNames);
    }

    function getTagMeta(bytes32 tagHash, address from) public view returns (MetaDataOutput memory) {
        MetaData storage meta = tags[tagHash].metas[from];
        return MetaDataOutput(meta.meta, meta.like, meta.dislike, meta.userlike[msg.sender]);
    }

    // 通过dataHash, 查询这个data有哪些tag
    function getDataTags(bytes32 dataHash) public view returns (bytes32[] memory) {
        return datas[dataHash].tags;
    }

    // 通过dataHash和tagHash，查询tag在这个data上的meta信息
    function getDataTagMeta(bytes32 dataHash, bytes32 tagHash) public view returns (MetaDataOutput memory) {
        MetaData storage meta = datas[dataHash].tag_info[tagHash];
        return MetaDataOutput(meta.meta, meta.like, meta.dislike, meta.userlike[msg.sender]);
    }
}