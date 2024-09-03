TAG系统：
1. 新建TAG需要审核，不能随意新建
    有固定的账户用来创建tag
2. TAG是一个分层结构，但TAG间又是相互独立的，一个TAG会有至多一个父TAG，和多个子TAG
3. TAG不能重名

TAG和数据的关系：
1. 一个用户可以给一个数据附加多个TAG
2. 多个用户可以给同一个数据附加不同的TAG
    问题：每个用户附加的TAG不同。这些TAG是可以被所有人看到？还是只能被自己看到？
    根据关系4，数据的TAG可以被所有人看到
3. 何时给数据附加TAG：
    1. 在中心系统SHOW之前，需要"下载"以消耗空间，下载时对数据附加TAG
    2. 用户收藏数据时，给数据附加TAG
4. 数据的TAG可以被所有人看到，可以支持/反对数据的某个TAG
5. TAG有自己的元数据
    问题：TAG的元数据谁可以编辑？

问题：数据的TAG是否可以被编辑或删除？谁有权限编辑或删除？

问题：数据的TAG是否会对数据SHOW的逻辑产生影响？

考虑将TAG作为一个独立的合约，而不是公共数据的一部分
```c
struct Tag {
    string name;
    string desc;
    bytes32 parent;     // parent为0表示顶层TAG
    bytes32[] children; // 考虑一个TAG的子TAG不会很多
    // 由于TAG可能包括很多数据，合约里不提供反向查询，靠后端扫描事件来重建数据库
}

mapping(bytes32 => Tag) public tags;    // 由name的hash做key

struct DataTagInfo {
    bool valid;                         // valid为true，表示数据有这个tag。因为solidity的map始终返回值
    uint128 like;                       // 如果考虑gas cost，这个字段可以取消
    uint128 dislike;                    // 如果考虑gas cost，这个字段可以取消
    mapping(address => int8) userlike;  // 1代表赞，0代表不点，-1代表否
}

struct Data {
    bytes32[] tags;                     // 这里用于遍历，或者返回一个数据关联的所有tag。如果考虑gas cost，这个字段可以取消
    mapping(bytes32 => DataTagInfo)     // 每个TAG的赞否数据，一个账户只能点一次赞或否
}

mapping(bytes32 => Data) public datas;  // 在被公共数据合约使用时，由mixhash做key,其他的合约可以有不同的data key使用方式
                                        // （这里会不会有问题？不同hash type的同一份数据会被视为不同的数据）

event TagCreated(bytes32 tagHash, bytes32 tagParent, string name)
event AddDataTag(bytes32 dataHash, bytes32 tag)
event RateDataTag(bytes32 dataHash, bytes32 tag, int8 like)

// 只列出写接口
contract DataTag {
    // 一次创建多层tag，已创建的tag会被忽略
    function createTag(string[] tags, string[] descs) {
        // 第一次创建了 /A/B，参数为[A, B]
        // 第二次创建了 /A/B/C，参数为[A, B, C], 只有C的内容会被写进链里
        emit TagCreated(hash(A), 0, A)
        emit TagCreated(hash(B), A, B)
        emit TagCreated(hash(C), B, C)
    }

    // 添加多个tag. 已添加的tag不会被添加. 不需要输入tag的完整路径
    function addDataTag(bytes32 dataHash, bytes32[] tags) {
        for tag of tags {
            emit addDataTag(dataHash, tag)
        }
    }

    // 赞/踩/取消 都用同一个接口，未被添加的tag会返回错误
    function rateDataTag(bytes32 dataHash, bytes32 tag, int8 like) {
        emit RateDataTag(dataHash, tag, like)
    }
}
```