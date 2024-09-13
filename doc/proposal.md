### createProposal(string calldata _title, string calldata desc, uint256 duration)
> 创建提案
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