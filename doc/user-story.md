# ETH 公共数据存储 玩法的Review

## 非主合约的关键实现
### GWT合约的相关实现
1. GWT是一个特殊的ERC20,不允许用户之间转账，只允许用户和几个认证合约之间的转账
2. GWT没有上限，可以在合约逻辑的随时Mint

### DMC合约的相关实现
支持Mint
支持跨链兑换

### GWT兑换合约的相关实现
支持升级
支持GWT<->DMC的固定汇率兑换：1个DMC换210个GWT

### NFT Bridge合约
支持IERCPublicDataContract
尽可能的导入更多的NFT项目


## 基金会视角的合约调用顺序
创建GWT合约
创建DMC合约
创建GWT兑换合约(GWT合约，DMC合约)
创建 NFT Bridge合约
创建公共数据存储合约（GWT合约，NFT Bridge合约）
初始化GWT合约，设置GWT兑换合约地址和公共数据存储合约地址，等待设置存储交易市场合约地址
    存储交易市场合约地址我们计划通过ETH 的 L2实现，正在OKX1上测试



### 定期运营活动：
给DMC合约设置正确的跨链信息
给DMC合约冲入足够的可MintDMC
选一批公共数据进行初始赞助
注意奖池的吸引力，让每期奖励有50W DMC
DMC上DeFi
注意降低DMC主网的DMC产出，或则延迟质押时间，减少DMC主网流流动性的溢出对新生态的影响。


### 基金会抽成
1. 奖池的5%
2. 挑战奖励的20%（比如用户通过挑战得到了1000个GWT，基金会会得到200个）

## 如何得到DMC？
特别注意的是，在用户看来使用DMC的操作，实际上我们是分成了的两部分的
1. DMC兑换得到GWT
2. 质押GWT
因此需要仔细的考虑产品设计，让用户减少兑换GWT的手续费开销

### 老矿工
调用DMC上的销毁合约，填写chainid+地址
调用 DMC合约的体现方法，得到DMC

### 新用户
1. 通过DeFi的方式购买DMC
2. 调用DMC合约的Mint方法
    计算上联Hash和调用地址的关系
    第一次Mint，得到默认的运气值
    非第一次Mint，根据和上一次Mint的距离得到运气值
    基于运气值，msg.sender,block.hash计算是否中奖
    中奖得到210 DMC，未中奖得到42DMC
    系统空投池要有足够的DMC才能成功

## Owner视角的合约调用顺序
1. 得到自己的NFT List，观察这些NFT是否已经被Sponosr。
2. 如果没有被Sponsr,或则余额太低，可以自己去调用createPublicData 或 addDeposit 
3. 观察自己的作为Owner赢得的Award，并在合适的时候调用Award提现
4. 经常分享自己拥有的NFT的数据Hash，让更多的人来Sponsor或SHOW数据

### 如何确定PublicData的Owner？
1. 固定Owenr,Sponsor就是Owner
2. 指定NFT合约，但未指定Index，这说明指该合约有查询数据Owner的方法。目前可以配置的就是我们的NFT Bridge合约，这种情况下Owner就是NFT Bridge合约的Owner
3. 指定NFT合约和Index,是指该数据的Owner就是特定NFT合约和Index的Owner。这种指定方法是我们最推荐的，可以和现在NFT生态很好的结合。但为了提高可信性，我们要求建立这种关系是可验证的。

#### 公共数据与NFT Owner的可验证连接
1. NFT合约本身实现了ERCXXXPublicData接口 （新NFT合约）
2. 官方的NFT Bridge合约实现了ERCXXXPublicData接口，并可查询到对应NFT合约 （已存NFT合约）

## Sponosr视角的合约调用顺序

### 创建一个新的公共数据
找打一个未被创建的公共数据MixHash,然后调用
```
function createPublicData(
    bytes32 dataMixedHash,
    uint64 depositRatio, //默认为 64，文件大小为1G，矿工需要锁定1*depositRatio*24的质押币 (SHOW相当于用户承诺保存24周)
    uint256 depositAmount, //希望打入的GWT余额
    address publicDataContract,
    uint256 tokenId
)
```
公共数据在创建时可以设置质押率depositRatio，会影响SHOW数据时需要冻结的GWT数量。
按目前的默认值，最小的文件为0.1G，则需要的GWT为
```
1G * 64质押率  * 96周   = 6144 GWT （约30 DMC）
```
系统对质押率有最小要求，也对时长有最小要求(96周)
在UI上，如果这个最小值小于50，我们的默认值是50 DMC（一次mint可以创建4个公共数据

### 赞助一个已有的公告数据
找到一个已有的公共数据，然后调用
```
addDeposit(bytes32 dataMixedHash, uint256 depositAmount) 
```
如果本次调用的depositAmount大于maxDeposit*110%,则会成为新的Sponsor

## 矿工视角的合约调用顺序
根据自己的空间进行初始质押->选择1个合适的数据->提交存储证明->等待挑战超时->提权奖励->解除质押
根据目标数据的余额准备初始质押->选择1个合适的数据->提交存储证明->等待挑战超时->提权奖励->解除质押



### 成为普通公共数据供应商
1. 得到DMC：Mint/购买 (DeFi)
2. 按1：210兑换GWT并全部质押
3. 调用 pledgeGWT，得到有效的存储空间。根据现在的公式，保存32G空间需要
```
32G * 64质押率  * 24周   = 49152 GWT （约234 DMC）
```

### 成为进取数据供应商
需要根据系统里头部数据的平均余额进行决定。
```
GWT = 平均余额 * 30，比如数据的平均余额为10000GWT，那么就需要准备300000 的DMC （约1500 DMC）
```
调用 pledgeGWT，得到有效的存储空间。根据现在的共识，需要额外增加约1500DMC

### 质押 SHOW 数据并得到奖励（手续费低，质押币需求高）
这里的质押是指根据SHOW收益决定的质押，和数据的Balance有关

调用函数：
```
//去掉PoW，因此只需要提交 m, path_m, m_leaf_data
function showDataEx(bytes32 dataMixedHash, uint256 nonce_block, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata) 
```
在Show后会立刻得到奖励，并增加数据的分数。但是需要等待一段时间才能解除质押
现在对质押的实现太消耗GAS了，可以更简单一点。

### 免质押SHOW数据 （手续费高，质押币需求低）
这里的质押是根据SHOW 数据大小的一般性质押，由系统决定而与Balance无关，目前对公共数据的质押率要求是创建数据时决定的，默认最小值是64倍）

调用函数
```
//去掉PoW，因此只需要提交 m, path_m, m_leaf_data
function showData(bytes32 dataMixedHash, uint256 nonce_block, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata) 
```
#### 提现Show数据
TODO：需要增加实现，针对showData的Index进行提现
在提现操作里增加数据的分数

### 解除质押
非冻结部分可以随时接触质押
冻结部分要看冻结时间，超过冻结时间可以解除质押。这样每次调用ShowData、ShowDataEx后，只需要简单的增加冻结时间就好了。

### 通过挑战赚钱
自己的SHOW操作如果没有在正确的区块上链，且系统已经有了一个SHOW记录，则自动变为挑战
挑战成功替换SHOW记录（本次替换不会增加数据的积分），并等待Timeout后可以提现自己的挑战奖励（比原奖励略少）。
```
function showData(bytes32 dataMixedHash, uint256 nonce_block, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata) 
```


## Award计算
每个周期的奖励 = 上个周期的奖励 * 0.15 + 这个周期的所有赞助 * 0.2， 每个周期奖池的0.05会作为基金会的收入
发放奖励的规则：每周期内奖池分配： 第一名记240分，依次递减，最后一名记13分。按照 总奖池* 0.8 * 自己的分数/总分数得到奖励
完整的奖励积分分配如下：
``` 
	1.240
	2.180	
	3.150
	4.120
	5.100
	6.80
	7.60
	8.50
	9.40
	10.35
	11.34
	12.33
	13.32
	14.31
	15.30
	16.29
	17.28
	....
	32.13	
```

链上只保存前32名，按现在的需求需要展示前50名，需要后台做一些计算。


### 周期规则
1. 每次有用户Sponosr数据，都会有20%进入奖池
2. 当触发上面行为时，可能会触发cycle更新。cycle更新时会固定上一个周期的数据并开启下一个周期



### 提取Award
用户认为和自己有关的数据赢得了某个周期的Award，就可以通过调用下面函数来提现
```
function withdraw(uint cycleNumber, bytes32 dataMixedHash)
```
上述函数的基本逻辑是
1. 定位周期信息
2. 确认用户与数据的关系
3. 计算数据的award
4. 提现，并标记用户已经在该数据里完成了提现
