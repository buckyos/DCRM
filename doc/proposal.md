### createProposal(string calldata _title, string calldata desc, uint256 duration)
> 创建普通提案
> - _title 提案标题，任意字符串
> - desc 提案内容，任意字符串
> - 提案持续时长，单位为秒，最大为3天
>
> 提案发起者必须事先在分红合约内质押至少(minStack) DMCX。提案创建成功后，发起者的质押锁定期变为3天后
> minStack的值在合约部署时确定，目前为 50000*10**18 wei
>

### supportProposal(uint256 id, string calldata desc)
> 投票支持提案
> - id: 提案ID
> - desc：投票意见
> 每个投票人只能对提案进行一次投票，票数为他投票当时在分红合约内质押的DMCX数量。单位为wei
> 
> 如果投票人没有质押，该操作无效。这笔交易会被视为成功。会消耗少量手续费
> 
> 投票成功后，投票人的质押锁定期变为3天后
>
### supportProposal(uint256 id, string calldata desc)
> 投票反对提案
> - id: 提案ID
> - desc：投票意见
> 每个投票人只能对提案进行一次投票，票数为他投票当时在分红合约内质押的DMCX数量。单位为wei
> 
> 如果投票人没有质押，该操作无效。这笔交易会被视为成功。会消耗少量手续费
> 
> 投票成功后，投票人的质押锁定期变为3天后

### getProposalCount() view public returns (uint256)
> 返回总提案数量
>

### getProposal(uint256 id) public view returns (ProposalBrief memory)
> 返回提案信息
> ```
>struct ProposalBrief {
>        string title;  // 提案标题
>        string desc;   // 提案内容
>        uint256 endtime;   // 提案截止时间
>        uint256 totalSupport;  // 总赞同票数
>        uint256 totalOppose;   // 总反对票数
>       uint256 totalVotes;     // 总投票人数
>    }
> ```

### function getProposalVotes(uint256 id, uint256 page, uint256 size) public view returns (VoteInfo[] memory)
> 以分页查询的方式返回投票详情。投票数组按照投票时间从旧向新排列
> - id: 提案ID
> - page：要查询的页数
> - size：每页的投票详情个数
> - 返回：VoteInfo数组，当真正的详情个数不足size时，数组的大小为真实详情个数
> ```
>struct VoteInfo {
>        address voter; // 投票人地址
>        bool support;  // 支持或反对
>        uint256 amount;    // 投票数量，单位为wei
>        string desc;   // 投票意见
>        uint256 timestamp; // 投票时间
>    }
> ```

## 可执行提案的扩展
目前的提案都是一般提案，链上只保存提案的内容和投票信息，由组织在线下负责执行

考虑以后可能会增加一些特别(可执行)提案，这些提案的动作类型是固定的，在投票成功之后，直接在合约上触发执行，确保执行参数的正确性

参考SourceDao的提案合约设计：
- 一种可执行提案对应一个固定的动作，由合约升级来扩展可执行提案的种类
- 每个提案有ProposalType字段，每种可执行提案都对应一个不同的Type
- 每种可执行提案都有三个独立的接口，一个负责发起，一个负责执行，一个在投票失败后回退发起的副作用
- 发起，执行，回退接口都需要传入相同的提案参数，发起接口保存参数的hash，执行和回退接口验证参数的hash
- 可执行提案的desc建议传入一个json，json中明文保存参数
- 和普通提案不同，可执行提案必须传入一个最小票数限制，结算时小于这个票数的提案不可执行
- 考虑可执行提案的发起有某种权限控制，可以是基于身份的，也可以是基于经济的