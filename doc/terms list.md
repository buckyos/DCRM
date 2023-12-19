#  所有的术语

- Data Owner,通常是公共数据对应的NFT的Owner。Owner只能通过ETH 合约的状态来获得。
- 公共数据Hash（缩写为PH），高64bits是数据的大小，低192bits是数据默克尔树根节点的Hash.
- SHOW，调用ETH合约的接口，展示一个存储证明。包括序号，序号的默克尔路径，叶子节点的数据
- Balance,数据的余额，ETH合约状态。SHOW成功后会从余额中得到奖励
- Supplier/Miner,公共数据的保存者，通过SHOW操作来获得来自数据余额的奖励
- Sponsor,赞助者。ETH合约状态，任何记录在合约中的公共数据都有一个Sponsor。
- 分数(Score)，在一个Award周期里，公共数据被成功SHOW的次数。新周期开始时，所有公共数据的Score都会清0
- 积分(Point)，公共数据的历史总积分。只有赢得了有效的Award排名才会增加。
- Mint，值使用BRC20协议，在BTC网络里Mint DMC的行为。我们扩展了lucky Mint.
- 铭刻(Insribe)公共数据铭文，在BTC网络里铭刻公共数据的并构造基于Ordinal协议的NFTs。 铭刻会根据数据的大小和积分来收取DMC铭刻费用。铭刻成功后用户成为该公共数据的铭文Owner。
- 吟唱(Chant)，在BTC网络里吟唱公共数据铭文并获得大量DMC的行为。
- 铭文Owner,在BTC网络里通过Ordinal协议确认的，公共数据铭刻的Owner。
- 共鸣(Resonance)，在BTC网络里向公共数据铭文的Owner支付一笔费用，获得吟唱该公共数据铭文的资格
- DMCs Mint Pool，在BTC网路里，Mint/Chant行为得到的DMC，都来自该资产池。如果资产池里没有DMC，那么上诉操作即使成功也不会得到DMC。
