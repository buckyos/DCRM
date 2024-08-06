import math

#基础分 = f(data_size) = 999 / (1 + exp(-0.00000762939453125*(data_size-127,999,999))) + 1
def get_basic(data_size):
    x = 0
    start_size = 128*1024*1024
    if data_size > start_size:
        x = data_size - start_size
    return 999 / (1 + math.exp(-0.00000762939453125*(x))) + 1
#基本倍率 = f(data_points) =  19 / (1 + e^(-0.15(data_points-90))) + 1
def get_basic_rate(data_points):
    return 19 / (1 + math.exp(-0.15*(data_points-90))) + 1

#n = 基础分*基础倍率
def get_n(data_size,data_points):
    return get_basic(data_size)*get_basic_rate(data_points)

def get_rate_by_size(data_size):
    if data_size < 1024*1024*128:#128MB 1.0
        return 1
    elif data_size < 1024*1024*1024*4:#4G 1.0 - 1.5
        return 1 + (data_size - 1024*1024*128)*0.5 / (1024*1024*1024*4-1024*1024*128)
    elif data_size < 1024*1024*1024*32:#32g 1.5-2
        return 1.5 +  (data_size - 1024*1024*1024*4)*0.5 / (1024*1024*1024*32-1024*1024*1024*4)
    elif data_size < 1024*1024*1024*1024:#1T 2-3
        return 2 +  (data_size - 1024*1024*1024*32) / (1024*1024*1024*1024-1024*1024*1024*32)
    else:
        return 4

def get_exp(mix_hash): 
    # 后面支持了新的公链，在这里增加别的链的show_count, polygen的权重估计只有0.1
    point_count = get_point_eth(mix_hash) * 8 + 0
    return 1+point_count # 如果积分是0，那么至少有1个exp

def get_level(exp):
    # 定义每个等级对应的经验值范围
    levels = [
        (1, 5), (5, 16), (16, 25), (25, 34), (34, 40),
        (40, 65), (65, 95), (95, 155), (155, 275), (275, 515),
        (515, 800), (800, 1500), (1500, 2500), (2500, 4000), (4000, 6000),
        (6000, 10000), (10000, 15000), (15000, 20000), (20000, 30000), (30000, 50000)
    ]
    
    # 遍历等级和对应的经验值范围
    for level, (min_exp, max_exp) in enumerate(levels, start=1):
        if min_exp <= exp < max_exp:
            return level
    # 如果经验值超出已定义的范围，返回最高等级
    return len(levels)
    

def get_n_by_level(level):
    # 等级对应的日收入
    income = [
        500, 1000, 1500, 2000, 2500,
        3000, 4000, 5000, 6000, 7000,
        8000, 9000, 10000, 15000, 20000,
        30000, 40000, 50000, 100000, 200000
    ]
    if level < 1:
        return 0
    # 根据等级返回日收入
    if 1 <= level <= 20:
        return income[level - 1]
    else:
        return 200000  # 如果等级不在已定义的范围内

# test 文件大小是1MB，连续在ETH上SHOW 7次后的效果
print(get_n_by_level(get_level(9)))
print(get_n_by_level(get_level(17)))
print(get_n_by_level(get_level(25)))
print(get_n_by_level(get_level(33)))
print(get_n_by_level(get_level(41)))
print(get_n_by_level(get_level(49)))
print(get_n_by_level(get_level(49)))