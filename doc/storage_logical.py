def _withdraw(order,usage,current_time):
    start_time = usage.last_with_draw
    end_time = current_time
    start_state = get_system_state(start_time)
    end_state = get_system_state(end_time)

    income = order.price * usage.size * (end_time - start_time)
    
    start_reward_rate = _get_from_carve(order.price * order.guaranteeRatio * start_state.reward_rate,start_state.total_size)
    end_reward_rate = _get_from_carve(order.price * order.guaranteeRatio * end_state.reward_rate,end_state.total_size)
    reward = (end_time - start_time) * usage.size * (end_reward_rate + start_reward_rate)/2

    daemon_rate = (start_state.deamon_rate + end_state.deamon_rate) / 2
    supply_rate = (start_state.supply_rate + end_state.supply_rate) / 2
    daemon_reward_rate = daemon_rate / (daemon_rate + supply_rate*order.guaranteeRatio)
    supply_reward_rate = (supply_rate * order.guaranteeRatio) / (daemon_rate + supply_rate*order.guaranteeRatio)

    daemon_reward = reward * daemon_reward_rate
    supply_reward = reward * supply_reward_rate
    system_income = reward - daemon_reward - supply_reward

    blance[system] = blance[system] + system_income - income
    blance[daemon] = blance[daemon] + daemon_reward
    blance[supply] = blance[supply] + supply_reward + income


def calcRewardRate(lastTotalSize,totalSize,lastRate):
    if(totalSize > lastTotalSize):
        growth = (totalSize - lastTotalSize)*56*6
        #相当于24周（半年）的增长率
        g_rate =  (growth*4 / totalSize)
        if(g_rate > lastRate):
            return g_rate
        return lastRate * (1+g_rate)
    else:
        decrise = (lastTotalSize - totalSize)*56*6
        d_rate = (decrise*4) / totalSize
        if(d_rate > 1):
            return getFromCarve(0)
        
        return lastRate*(1-d_rate)
