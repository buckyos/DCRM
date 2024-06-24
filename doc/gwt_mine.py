def mine_gwt(x):
    return 0.2 + (1.8*x) / (x + 1)

X = 0
while X<10:
    print(mine_gwt(X))
    X = X + 0.1