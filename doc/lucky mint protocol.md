# lucky mint protocol

## 摘要

1. 在Mint协议中增加了一个关键字“lucky”，用户可以在mint是保存一条自己的message
2. 带有lucky的mint称为lucky mint, lucky mint交易必须进入一个与用户地址相关的特定区块（可以称作幸运区块）才算lucky 生效
3. lucky生效后，用户得到的奖励是amount * 10

## 详细设计

幸运区块的确定：
```python
def is_lucky_mint(self, sender_address, block_height):
    address_num = btc_address_to_number(sender_address)
    if (block_height + address_num) % 8 == 0:
        return True
    else:
        return False
```

## 
