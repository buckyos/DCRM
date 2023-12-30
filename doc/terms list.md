##  DMCs相关术语

- 公共数据Hash（缩写为MixHash），用来唯一的标识一个公共数据。是我们发明的对公共数据存储证明友好的Hash算法。最高2bits是数据的Hash类型，然后62bits是数据的大小，低192bits是数据默克尔树根节点的Hash.
- 公共数据积分(Point)，简称积分。在ETH网络上矿工展示公共数据存储证明，赢得了有效的Award排名会增加。
- Mint，值使用BRC20协议，在BTC网络里Mint DMC的行为。每次Mint得到210个DMCs.我们扩展了lucky Mint.
- Lucky Mint，在现有Ordinal Mint协议的基础上，增加了Lucky Cookie字段。用户可以填写一段自定义文本进行Lucky Mint. 根据用户的地址，当Lucky Mint TX进入特定区块视作成功。成功的Lucky Mint会得到2100个DMC。失败得到210个DMC. 用户从DMC主网迁移过来的DMCs,也是通过特殊的Lucky Mint来获得.
- 铭刻(Inscribe)公共数据铭文，消耗DMCs并构造基于Ordinal协议的NFTs。 铭刻会根据数据的大小和积分来收取DMCs铭刻费用。铭刻成功后用户成为该公共数据的铭文Owner。
- 公共数据铭文，缩写为数据铭文，通过铭刻协议创建的，兼容Orinal协议的NFTs。
- 吟唱(Chant)，在BTC网络里吟唱公共数据铭文并获得大量DMC的行为。用户可以吟唱自己拥有的，和自己共鸣的公共数据铭文。
- 铭文Owner,在BTC网络里通过Ordinal协议确认的，公共数据铭刻的Owner。可以通过Ordinal协议的标准方法转移Owner。（支持各种NFTs交易）
- 共鸣(Resonance)，向公共数据铭文的Owner支付一笔约定的DMCs费用，获得吟唱该公共数据铭文的资格。1个功公共数据铭文3个月不吟唱的共鸣铭文会失去资格。数据铭文支持最多15个共鸣用户。
- 可Mint DMCs总量:在BTC网路里，Mint/Chant行为得到的DMC，依赖该总量。如果总量为0，那么上诉操作即使成功也不会得到DMC。 可Mint DMCs的总量 = 未Mint DMCs+ DMCs Mint Pool
- DMCs Mint Pool: 根据我们的规则，用户铭刻公共数据铭文的消耗的DMCs,98%会进入该Mint Pool。该Pool的系统初始值为0.

## DMC的ETH公共数据挖矿相关术语
- Data Owner,通常是公共数据对应的NFT的Owner。Owner只能通过ETH 合约的状态来获得。
- SHOW，调用ETH合约的接口，展示一个存储证明。包括序号，序号的默克尔路径，叶子节点的数据
- Balance,数据的余额，ETH合约状态。SHOW成功后Supplier会从余额中得到奖励
- Supplier/Miner,公共数据的保存者，通过SHOW操作来获得来自数据余额的奖励
- Sponsor,赞助者。ETH合约状态，任何记录在合约中的公共数据都有一个Sponsor。通过给公共数据赞助更多的Balance可以自动得到Sponosr资格
- 分数(Score)，在一个Award周期里，公共数据被成功SHOW的次数。新周期开始时，所有公共数据的Score都会清0
- Award结算。在一个周期里，得到的分数进入前32名且分数大于32的公共数据，会得到Award. 具体的数值按比例从Award Pool中分配。
