# 算力奖励的核心思路，是资本回报逻辑
# 矿工出售空间，质押了7500个 GWT，按质押率 3倍来算，在结束时可以得到2500个GWT的收入，那么通过算力奖励，要得到多少附加的GWT》
# 用户花了2500个GWT购买空间，那么通过算力奖励，其实际开销相当于打了几折呢？

# 因为我们不使用自动匹配机制，所以存在矿工左手倒右手的问题，一共是锁定了10000个GWT，那么其算力奖励的收入在2000GWT到 250GWT之间。
# 因为不使用自动匹配机制，无存储空间的矿工会Cancel不是自己左手的订单。系统通过增加Cancel时间提高了矿工的资金成本
# 用户一般不承担Cancel的手续费（因为锁定的资金比矿工少）
# Fake用户攻击，准备一些GWT，然后不断的去买空间，单不传数据等取消。这样的行为会导致整个DMC网络的实际GWT利用率低下。这样的用户行为是损人不直接利己的，比较适合GWT的大户来提高挖矿难度。

# 算力奖励与price无关，只和质押率有关。也就是说，站在提高算力的角度，系统鼓励高质押率，低价格的存储空间。

# x的含义是当前的增长率
def mine_gwt(x):
    return 0.2 + (1.8*x) / (x + 1)


def _calcRewardRation(lastSize,thisSize):
    x = 0.02
    if thisSize > (lastSize*1.02):
        x = thisSize / lastSize - 1

    #有一个基于thisSize的放大系数
    
    return mine_gwt(x)


def test_mint():
    X = 0
    while X<10:
        print(mine_gwt(X))
        X = X + 0.1

def test_cacl():
    size = 1024*1024
    while size < 1024*1024*1024:
        new_size = size + 1024*1024
        print(_calcRewardRation(size,new_size))
        size = new_size

test_cacl()
#test_mint()