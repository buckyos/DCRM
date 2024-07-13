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