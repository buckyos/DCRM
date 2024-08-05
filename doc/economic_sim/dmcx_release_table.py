n = 1
count = 1
for i in range(19):
    n = n * 0.8
    count = count + n
    

print(count)
init = ((50000*10000) / count) / 21
print(init)

token_count = init * 21
balance = token_count
for i in range (19):
    balance = balance * 0.8
    token_count += balance

print(token_count)