TAG系统：
1. 任何人都可以新建TAG
2. TAG是一个分层结构，一个TAG会有至多一个父TAG，和多个子TAG，TAG的全名是它的路径拼接
3. TAG的全名不能重复
4. 任何人都可以给TAG附加一个描述，每个人的描述是独立的
5. 任何账号都可以 赞同/反对 TAG的某个描述 
6. 在前/后端展示上，我们可以限定某些"认证"账号赞同的描述，才是一个tag的有效描述。存在有效描述的tag才是有效的tag
7. 必须要在合约端做一个无效字符判定，无效字符至少包括路径分隔符'/'

TAG和数据的关系：
1. 一个用户可以给一个数据附加多个TAG，此时，他可以选择给tag新增一个描述，或者使用某个已有的描述
2. 当用户给数据附加一个已有的描述时，看作对这个描述点赞同
3. 基于2，任何一个tag都默认有一个赞同，即tag的创建者的赞同
4. 多个用户可以给同一个数据附加不同的TAG
5. 何时给数据附加TAG：
    1. 在中心系统SHOW之前，需要"另存为"以消耗用户空间，此时对数据附加TAG
    2. 用户收藏数据时，给数据附加TAG。收藏可以看作一种轻量级的"另存为"
6. 任何账号都可以 赞同/反对 数据下的某个TAG

考虑将TAG作为一个独立的合约，而不是公共数据的一部分
```c

// 通用的，包含赞同/反对信息的Meta数据结构。tag和data-tag都会用到这个数据结构
struct MetaData {
    bool valid;                         // 这个结构通常用在mapping的value，用这个字段表示这个value是否为空
    string meta;                        // 元数据。在tag系统下，它是tag的描述；在data-tag系统下，它是附加这个tag的原因
    uint128 like;                       // 如果考虑gas cost，这个字段可以取消
    uint128 dislike;                    // 如果考虑gas cost，这个字段可以取消
    mapping(address => int8) userlike;  // 1代表赞，0代表不点，-1代表否
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
    string[] fullName;      // 直接返回整个路径
    bytes32 parent;
    bytes32[] children;
    // 因为使用哪种描述，是前/后端的逻辑，这里就不返回任何描述信息
    // TODO：考虑返回最后更新的描述信息，但这要多一个字段存储最后更新的地址，而且类似"编辑战争"，最后更新的描述不一定是更正确的描述
}

mapping(bytes32 => Tag) public tags;    // 由name的hash做key


// 先按照Data绑定tag来思考，tag展示哪个描述由UI决定
struct Data {
    bytes32[] tags;                 // 这里用于遍历，或者返回一个数据关联的所有tag。如果考虑gas cost，这个字段可以取消
    mapping(bytes32 => MetaData)    // 每个TAG的赞否数据，一个账户只能点一次赞或否
}

mapping(bytes32 => Data) public datas;  // 在被公共数据合约使用时，由mixhash做key,其他的合约可以有不同的data key使用方式
                                        // （这里会不会有问题？不同hash type的同一份数据会被视为不同的数据）

event TagUpdated(bytes32 tagHash, address from, bytes32 tagParent, string name)
event AddDataTag(bytes32 dataHash, bytes32 tag)
event RateTagMeta(bytes32 tagHash, address from, int8 like)
event RateDataTag(bytes32 dataHash, bytes32 tag, int8 like)

// 只列出写接口
contract DataTag {
    // 给tag设置meta，首次设置时，会被看作创建了这个tag
    // 输入是已经分割好的tag路径
    function setTagMeta(string[] tags, string desc) {
        // 设置/A/B/C
        emit TagUpdated(A, msg.sender, 0, "")
        emit TagUpdated(B, msg.sender, A, "")
        emit TagUpdated(C, msg.sender, B, descC)

        // 同一个人再设置/A/D
        emit TagUpdated(D, msg.sender, A, descD)

        // 不同的人设置/A/D
        emit TagUpdated(A, msg.sender, 0, "")
        emit TagUpdated(D, msg.sender, A, descD)
    }

    // 添加多个tag. 已添加的tag不会被添加. 需要输入tagID
    function addDataTag(bytes32 dataHash, bytes32[] tagids) {
        for tagid of tagids {
            emit addDataTag(dataHash, tagid)
        }
    }

    // 赞同/反对一个tag的描述
    function rateTagMeta(bytes32 dataHash, address from, int8 like) {
        emit RateTagMeta(dataHash, from, like)
    }

    // 赞同/反对一个数据被附加的tag
    function rateDataTag(bytes32 dataHash, bytes32 tagid, int8 like) {
        emit RateDataTag(dataHash, tagid, like)
    }
}
```