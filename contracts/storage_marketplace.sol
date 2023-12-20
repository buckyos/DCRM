// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./gwt.sol";

import "hardhat/console.sol";


contract StorageExchange {
    GWTToken public gwtToken;// Gb per Week Token

    struct StorageSupplier {
        address ceo;//可以修改其它职位，拥有最高权限。其私钥很少使用。
        address cfo;//财务操作
        address[] operators; //其它操作（比如矿机的自动化操作）
        string[] urlprefixs; //可以修改 比如 https://www.hostname.com/get/
        address[] LPs;//其它股东
        uint32 longitude;
        uint32 latitude;
    }
    
    enum UsageStatus {Waiting, Active, ChallengeSuccess, Cancelled,Ended,CancelledFromWait,Lost}
    struct StorageUsage {
        address buyer;
        uint64 size;
        UsageStatus status;
        uint64 createPeriod;//创建时间
        uint64 effectivePeriod;//计划结束时间,TODO:简单实现可以和order的effectivePeriod一致
        uint64 activePeriod; //变成激活状态的时间
        uint64 endPeriod;//从激活变成非激活状态的时间
        
        bytes32 challengeHash;
        uint64 challengePeriod;
        uint64 declearPeriod;
        uint64 lastWithDrawPeriod;

        uint64 orderId;
    }

    enum OrderStatus {Waiting,  Active, OnLeave, Cancelled , Ended}
    struct StorageOrder {
        uint64 size;
        uint16 quality;// 年故障率（不允许填0），这个值越大，越有概率系统返还保证金。
        uint16 price;//单位是128的倍数。最小值为 16 (12.5%) 最大值为 1024 (8倍),比如256表示2个GWT/week
        uint8 guaranteeRatio;//质押率，单位是16的倍数。最小值为 8（0.5倍），最大值为 256 (16倍)
        uint64 createPeriod; //创建时的周期编号
        uint64 effectivePeriod;//结束时的周期编号

        uint64 minimumPurchaseSize;
        uint64 supplierId;
        OrderStatus status;
        uint64 remainingSize;
        uint64 leavePeriod;//如果当前处于请假状态，本次请假的区块高度
        uint8 leaveCount;//已经请假的总次数
        //mapping(bytes32 => StorageUsage) buyers;
    }

    
    struct SystemState {
        uint256 blockNumber;//本周期的开始区块高度
        uint128 totalActiveSize;
        uint128 totalSupplyOrderSize;
        uint128 totalDemandOrderSize;

        uint8 supplyRatio; //16为1倍，最大值为 256 (16倍)
        uint8 demandRatio; //16为1倍，最大值为 256 (16倍)
        //uint8 systemRatio; //计算算力奖励时，不给系统的比例，取值范围时（0，1）
        uint16 rewardRate;//rewardRate 算力奖励的比例.用uint16表达的浮点数，逻辑范围是: (0, 2)
        //uint16 taxRate;//交易结算时，给到系统的交易费用比例

    }


    uint64 public nextOrderId = 0;
    mapping(uint64 => StorageOrder) public orders;
    
    mapping(uint64 => StorageSupplier) public all_suppliers;
    uint64 public nextSupplierId = 1;

    mapping(uint64 => SystemState) public all_system_states;
    // all_system_states[0]为初始参数
    uint64 public currentPeriod = 0;

    mapping(bytes32 => StorageUsage) public all_usage;//用于验证rootHash是否已经使用过

    uint256 public sysGWTAmount = 0;
    uint8 public sysPeriodPerWeek = 56; //一周是56个周期
    uint256 public sysFixPeriodPerWeek = 0;
    uint16 public sysMinPrice = 16; //最小价格，单位是128的倍数。最小值为 16 (12.5%) 最大值为 1024 (8倍)
    uint8 public sysMinGuaranteeRatio = 8; //最小质押率，单位是16的倍数。最小值为 8（0.5倍），最大值为 256
    //uint8 systemRatio; //计算算力奖励时，不给系统的比例，取值范围时（0，1）
    uint64 public sysMinEffectivePeriod = 56*24; //最小有效周期为 24周，一周是56个周期，24*56
    uint64 public sysMinActivePeriod = 2;//从wait转到active的最小周期
    uint32 public sysMinPurchaseSize = 1024*1024*1024*2;//2G 
    uint64 public sysMinSupplierSize = 1024*1024*1024*32;//32G
    uint64 public sysMinDemandSize = 1024*1024*1024*4; //4G
    uint64 public sysMinChallengeDuration = 56;//两次挑战之间的最小间隔周期
    uint64 public sysChallengeTimeout = 56;//挑战超时（供应方认输时间）
    uint256 public sysDeclearFee = 64 * (10 ** uint256(18)); //诉讼费用
    uint256 public sysMinLeaveDuration = 56*8;//两次请假之间的最小间隔是8周
    uint8 public sysMaxLeaveCount = 2; //每年（48周）能请假两次？
    uint16 public sysFirstWithDrawPeriod = 56*6;//第一次提现的周期
    uint16 public sysBlockPerPeriod = 4*60*3;//以太坊平均15秒1个块，一个周期是3小时

    event SupplierCreated(uint64 supplierId);
    event SupplierChanged(uint64 supplierId);
    event StorageOrderCreated(uint64 orderId);
    event StoragePurchased(uint64 orderId, address buyer, uint64 size);
    

    constructor(address _gwtTokenAddress) {
        gwtToken = GWTToken(_gwtTokenAddress);
        nextOrderId = 0;
        //sysFixPeriodPerWeek = (10**18 / 128) / sysPeriodPerWeek;
        // 之前这里除以128是为了处理price的128倍数，移到正确的_calcTotalPrice函数中处理
        // 10**18 / 56本身就会造成精度损失，这里试试不再除以这个值
        sysFixPeriodPerWeek = sysPeriodPerWeek;
        //为了减少除零风险，系统初始化时有1TB的算力，供需双方各10GB的挂单算力，并且已经有了2个已知的系统状态
        // 配置系统初始化的初值
        SystemState memory init_state = SystemState(
            block.number,
            1024**4,    // totalActiveSize
            10*1024**3, // totalSupplyOrderSize
            10*1024**3, // totalDemandOrderSize
            16,         // supplyRatio
            16,         // demandRatio
            32768       // rewardRate, 按照注释，rewardRate >> 15是一个0~2的浮点，那么32768 >> 15就正好等于1
            );
        all_system_states[0] = init_state;

        // 启动的周期算是第一个周期
        all_system_states[1] = init_state;
        currentPeriod = 1;
    }

    function _getSystemStateIndexFromBlockNumber(uint64 currentPeriodStartBlockNumber,uint64 blockNumber) private view returns (uint64) {
        if(blockNumber < currentPeriodStartBlockNumber) {
            return currentPeriod - (currentPeriodStartBlockNumber - blockNumber) / sysBlockPerPeriod;
        } else if (blockNumber > currentPeriodStartBlockNumber) {
            return (blockNumber - currentPeriodStartBlockNumber) / sysBlockPerPeriod + currentPeriod;
        } else {
            return currentPeriod;
        }
    }

    function _getSystemRatio(uint128 /* totalActiveSize */) private pure returns (uint8) {
        return 127;
    }

    //结算周期，1天8次，每次约3小时，一个Week等于56个peroid
    function _getSettlementPeriod(uint64 blockNunmberDistance) private view returns (uint64) {
        return blockNunmberDistance / sysBlockPerPeriod;
    }

    function _getBlockNumbDistanceFromPeriodCount(uint64 currentPeriodStartBlockNumber,uint64 periodCount) private view returns (uint64) {
        return currentPeriodStartBlockNumber + periodCount * sysBlockPerPeriod;
    }



    function _isValidOperator(StorageSupplier storage supplier_, address operator) private view returns (bool) {
        for (uint i = 0; i < supplier_.operators.length; i++) {
            if (supplier_.operators[i] == operator) {
                return true;
            }
        }
        return false;
    }

    function _mintGWT(uint256 /* amount */,address /* target */) private {
        //TODO
    }

    //输入x是用uint256表达的浮点数，其定点逻辑与返回值相同（取值范围是 (0,)）;返回一个用uint16表达的浮点数，返回值的逻辑范围是: (0, 2)
    function _getFromCave(uint256 /* x */,uint128 /* totalSize */) private pure returns (uint16) {
        //TODO
        return 1<<15;
    }

    function _calcReward(uint64 periodCount,uint64 size,uint16 price,uint8 guaranteeRatio,
                         SystemState storage start_state,SystemState storage end_state) private view returns (uint256) {
        //price的单位是用uint16标示的标准倍数，其中 128为1倍，系统最小值为16，最大值为 1024， >>7
        //guaranteeRatio, 8（0.5倍），16 (1倍） 最大值为 256 (16倍)       >>4  
        //rewardRate 算力奖励的比例.用uint16表达的浮点数，逻辑范围是: (0, 2)  >>15
        
        // 组合起来需要 >> 11
        uint256 end_reward_rate = _getFromCave((uint256(price) * uint256(guaranteeRatio) >> 11)* uint256(end_state.rewardRate),end_state.totalActiveSize);
        uint256 start_reward_rate = _getFromCave((uint256(price) * uint256(guaranteeRatio) >> 11)* uint256(start_state.rewardRate),start_state.totalActiveSize);
        
        // 组合起来需要 >>26,算平均数/2,总共>>27
        //periodCount * size * (end_reward_rate + start_reward_rate) / 2
        return uint256(periodCount) * uint256(size) * sysFixPeriodPerWeek * (end_reward_rate + start_reward_rate) >> 27;
    }


    function _calcTotalPrice(uint64 periodCount,uint16 price,uint64 size) private view returns (uint256) {
        //price的单位是用uint16标示的标准倍数，其中 128为1倍，系统最小值为16，最大值为 1024
        // sysFixPeriodPerWeek = (10**18 / sysPeriodPerWeek)/128, 10**18是为了避免小数点,sysPeriodPerWeek=56
        // periodCount * (price >> 7) * size * sysFixPeriodPerWeek得到对应的GWT Token数量，再乘以10**gwtToken.decimals()得到对应的最小单位数量
        // return (periodCount * price * size * sysFixPeriodPerWeek * 10**gwtToken.decimals()) >> 7;

        // size(GB) * (price/128) * effectivePeriod / sysFixPeriodPerWeek
        // byte -> GB 是>> 30，price转倍数是>> 7，加起来是 >> 37
        
        return ((size * price * periodCount * (10**gwtToken.decimals())) >> 37) / sysFixPeriodPerWeek;
    }

    function _calcDeposit(uint256 totalPrice,uint8 guaranteeRatio) private pure returns (uint256) {
        return (totalPrice * guaranteeRatio)>>4;
    }

    function createSupplier(address cfo,address[] calldata operators, string[] calldata urlprefixs,uint32 longtitude,uint32 latitude) public {
        all_suppliers[nextSupplierId] = StorageSupplier(msg.sender,cfo,operators,urlprefixs,new address[](0),longtitude,latitude);
        nextSupplierId++;
        emit SupplierCreated(nextSupplierId-1);
    }

    function updateSupplier(uint64 supplierId,address cfo,address[] calldata operators, string[] calldata urlprefixs) public {
        StorageSupplier storage supplier_ = all_suppliers[supplierId];
        require(msg.sender == supplier_.ceo, "Only ceo can update supply info");
        supplier_.cfo = cfo;
        supplier_.urlprefixs = urlprefixs;
        supplier_.operators = operators;

        emit SupplierChanged(supplierId);
    }

    function supplier(uint64 supplierId) public view returns (StorageSupplier memory) {
        return all_suppliers[supplierId];
    }

    //创建订单，大部分情况是供应单，也可以是需求单
    function createStorageOrder(uint64 supplierId, uint64 size, uint16 quality, uint16 price, uint64 effectivePeriod, uint64 minimumPurchaseSize,
                                uint8 guaranteeRatio, bytes32 rootHash) public {
        updateComputeState();
        require(effectivePeriod >= sysMinEffectivePeriod, "Effective time too short");
        require(price >= sysMinPrice, "Price too low");
        uint256 totalPrice = _calcTotalPrice(effectivePeriod, price,size);
        uint256 depositAmount = _calcDeposit(totalPrice,guaranteeRatio);
        require(depositAmount >= (totalPrice * sysMinGuaranteeRatio)>>4, "Deposit amount too small");
        
        if(supplierId != 0) {
            StorageSupplier storage supplier_ = all_suppliers[supplierId];
            require(msg.sender == supplier_.cfo, "Only cfo can create order");
            require(minimumPurchaseSize >= sysMinPurchaseSize, "Minimum purchase size too small");
            gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        } else {
            require(size >= sysMinDemandSize, "size less than min demand size");
            require(minimumPurchaseSize == size, "size MUST equal minimumPurchaseSize");
            //需求方依旧可以通过depositAmount要求质押率
            gwtToken.transferFrom(msg.sender, address(this), totalPrice);
        }

        SystemState storage state = all_system_states[currentPeriod];

        StorageOrder storage order_ = orders[nextOrderId];
        order_.size = size;
        order_.quality = quality;
        order_.price = price;
        order_.guaranteeRatio = guaranteeRatio;
        order_.createPeriod = currentPeriod;
        order_.effectivePeriod = currentPeriod + effectivePeriod;
        order_.minimumPurchaseSize = minimumPurchaseSize;
        order_.status = OrderStatus.Waiting;
        order_.remainingSize = size;
        order_.leaveCount = 0;
        order_.leavePeriod = 0;

        if(supplierId != 0) {
            order_.supplierId = supplierId;
            state.totalSupplyOrderSize += size; 
        }else{
            order_.supplierId = 0;
            all_usage[rootHash] = StorageUsage(msg.sender,
                size,
                UsageStatus.Waiting,
                currentPeriod,
                effectivePeriod,
                0,
                0,
                0,
                0,
                0,
                0,
                nextOrderId);

            state.totalDemandOrderSize += size;
        }

        emit StorageOrderCreated(nextOrderId);

        nextOrderId++;
    }

    
    function order(uint64 orderId) public view returns(StorageOrder memory) {
        return orders[orderId];
    }

    //向一个订单购买存储空间
    function buyStorage(uint64 orderId, uint64 size,bytes32 rootHash,uint64 duration) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.size == 0, "Usage Already exists");
        require(order_.status == OrderStatus.Waiting || order_.status == OrderStatus.Active, "Only waiting or active order can be bought");
        require(order_.remainingSize >= size, "Not enough storage available");
        require(size >= order_.minimumPurchaseSize, "size too small");
        //还有足够的有效期,TODO所有处理有效期为周的地方都要检查
        require(order_.effectivePeriod > currentPeriod, "order has invalid");
        require(order_.effectivePeriod - currentPeriod >= duration, "order not enough effective time");
        //只有订单创建开始一小段时间后，才能购买
        require(currentPeriod - order_.createPeriod > sysMinActivePeriod, "wait order active");
       
        uint256 totalPrice = _calcTotalPrice(duration, order_.price, size);
        gwtToken.transferFrom(msg.sender, address(this), totalPrice);
        
        SystemState storage state = all_system_states[currentPeriod];
        usage_.buyer = msg.sender;
        usage_.createPeriod = currentPeriod;
        usage_.effectivePeriod = duration;//在active之前这里保存的是购买时长，active后变成结束时间 （能节约gas fee么？）
        //usage_.effectivePeriod = currentPeriod + (order.effectivePeriod);
        usage_.status = UsageStatus.Waiting;
        usage_.size = size;

        order_.status = OrderStatus.Active;
        order_.remainingSize -= size;
        state.totalSupplyOrderSize -= size;
        emit StoragePurchased(orderId, msg.sender, size);
    }

    function usage(bytes32 rootHash) public view returns(StorageUsage memory) {
        return all_usage[rootHash];
    }

    //向一个订单发送报价意向
    // 成交一个买单，是不是该用这个函数？缺少Usage的处理逻辑？但为什么叫报价意向？还有竞价的逻辑么？
    function makeOffer(uint64 supplierId,uint64 orderId,bytes32 /* rootHash */) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId == 0, "Only demand orders can receive offers");
        require(order_.status == OrderStatus.Waiting, "Only waiting order can receive offers");
        //只有订单创建开始一小段时间后，才能报价
        require(currentPeriod - order_.createPeriod > sysMinActivePeriod, "wait order active");
        require(order_.effectivePeriod - currentPeriod <= sysMinEffectivePeriod, "wait order active");
        StorageSupplier storage supplier_ = all_suppliers[supplierId];
        require(_isValidOperator(supplier_,msg.sender), "Only operator can make offer");
        uint256 depositAmount = _calcDeposit(_calcTotalPrice(order_.effectivePeriod - currentPeriod, order_.price, order_.size),order_.guaranteeRatio);

        gwtToken.transferFrom(supplier_.cfo, address(this), depositAmount);
        order_.supplierId = supplierId;
        order_.status = OrderStatus.Active;
        order_.createPeriod = currentPeriod;//让订单看起来像是刚刚创建的

        SystemState storage state = all_system_states[currentPeriod];
        state.totalDemandOrderSize -= order_.size;
    } 

    // 取消订单
    // TODO:已经事实上没有usage的订单是否可以取消？这里的计算有点复杂
    // TODO:处理买单取消应该另开一个函数？
    function cancelOrder(uint64 orderId) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require((order_.supplierId !=0), "Only standard order can be cancelled");

        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        require(_isValidOperator(supplier_,msg.sender), "Only operator can cancelOrder");
        require(order_.status == OrderStatus.Waiting, "Only waiting order can be cancelled");
        order_.status = OrderStatus.Cancelled;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalSupplyOrderSize -= order_.size;

        //TODO:挂单奖励
        uint256 depositAmount = _calcDeposit(_calcTotalPrice(order_.effectivePeriod - currentPeriod, order_.price, order_.size),order_.guaranteeRatio);
        gwtToken.transferFrom(address(this), supplier_.cfo, depositAmount);
    }

    //释放限制空间并返还对应的保证金
    function freeOrderSpace(uint64 orderId,uint64 freeSize) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        require((order_.supplierId !=0), "Only standard order can be free");
        require(order_.status == OrderStatus.Active, "Only active order can be free");
        uint64 willFreeSize;
        if(currentPeriod > order_.effectivePeriod) {
            order_.status = OrderStatus.Ended;
            willFreeSize = order_.remainingSize;
        } else {
            willFreeSize = freeSize;
            require(willFreeSize <= order_.remainingSize, "free size too large");
            order_.remainingSize -= willFreeSize;
        }
        require(_isValidOperator(supplier_, msg.sender), "Only operator can freeOrderSpace");

        SystemState storage state = all_system_states[currentPeriod];
        state.totalSupplyOrderSize -= willFreeSize;

        //TODO：处理挂单奖励？严格的计算比较复杂，简单的计算要防止套路
        uint256 depositAmount = _calcDeposit(_calcTotalPrice(order_.effectivePeriod - order_.createPeriod,order_.price,willFreeSize),order_.guaranteeRatio);
        gwtToken.transferFrom(address(this), all_suppliers[order_.supplierId].cfo, depositAmount);
    }

    function confirmUsageRoot(uint64 orderId,bytes32 rootHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        StorageUsage storage usage_ = all_usage[rootHash];

        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.buyer != address(0), "No such rootHash");
        require(usage_.status == UsageStatus.Waiting, "Already confirmed");
        require(_isValidOperator(supplier_,msg.sender), "Only operator can confirm usage");

        usage_.status = UsageStatus.Active;
        usage_.activePeriod = currentPeriod;
        usage_.effectivePeriod = currentPeriod + order_.effectivePeriod;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize += usage_.size;
    }

    //TODO：一方提出友好离开，另一方同意后，订单结束。不扣保证金
    // function cancelUsage(uint64 orderId,bytes32 rootHash) public {

    // }
    //end & withdraw: 
    // function confirmCancel(uint64 orderId,bytes32 rootHash) public {

    // }


    // 发起存储挑战
    function challenge(uint64 orderId,bytes32 rootHash, bytes32 challengeHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId != 0, "Only standard order can be challenged");
        
        if(order_.status == OrderStatus.OnLeave) {
            if(currentPeriod - order_.leavePeriod > sysMinLeaveDuration) {
                order_.status = OrderStatus.Active;
                order_.leavePeriod = 0;
            }
        } else {
            require(order_.status == OrderStatus.Active, "Order not active");
        }

        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.declearPeriod == 0, "Already decleared challenge illegal");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(currentPeriod - usage_.challengePeriod > sysMinChallengeDuration, "Challenge too frequent");

        usage_.challengeHash = challengeHash;
        usage_.challengePeriod = currentPeriod;
    }

    // 响应简单挑战
    function respondChallenge(uint64 orderId, bytes32 rootHash,bytes calldata rawData) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId == 0, "Only demand order can be challenged");

        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(usage_.challengeHash != 0, "No challenge initiated");
        require(currentPeriod - usage_.challengePeriod <= sysChallengeTimeout, "Challenge expired");

        bytes32 responseHash = keccak256(rawData);
        require(responseHash == usage_.challengeHash, "Respond Challenge failed");
        usage_.challengeHash = 0;
    }

    //end & withdraw:  超时后，确认挑战成功，并提款 DONE
    function challengeSuccess(uint64 orderId, bytes32 rootHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId == 0, "Only demand order can be challenged");

        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(usage_.challengeHash != 0, "No challenge initiated");
        require(currentPeriod - usage_.challengePeriod > sysChallengeTimeout, "Challenge is not expired!");

        usage_.status = UsageStatus.ChallengeSuccess;
        usage_.endPeriod = usage_.challengePeriod;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage_.size;
        //order_.remainingSize += usage_.size; 扣除保证金

        //以挑战时间为结束时间计算算力奖励
        //buyer:支付挑战时间以前的费用，获得保证金和诉讼费用（手续费补贴）
        //supplier:获得支付挑战时间以前的费用。
        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        uint64 startPeriod = usage_.lastWithDrawPeriod == 0?usage_.activePeriod:usage_.lastWithDrawPeriod;
        SystemState storage end_state = all_system_states[usage_.challengePeriod];
        SystemState storage start_state = all_system_states[startPeriod];
        //供应商提取的是1）buyer按比例的费用 2)算力奖励
        //buyer提取的是：算力奖励
        uint256 supplierIncome =  _calcTotalPrice(usage_.challengePeriod - startPeriod, order_.price, usage_.size);
        uint256 depositAmount = _calcDeposit(_calcTotalPrice(usage_.effectivePeriod - usage_.activePeriod,order_.price,usage_.size),order_.guaranteeRatio);
        uint256 reward = _calcReward(usage_.challengePeriod - startPeriod, usage_.size,order_.price,order_.guaranteeRatio,start_state,end_state);
        
        //supplyRatio:16为1倍，最大值为 256 (16倍)
        uint32 supplyRatio = uint32(end_state.supplyRatio + start_state.supplyRatio) / 2;
        uint32 demandRatio = uint32(end_state.demandRatio + start_state.demandRatio) / 2;
       
        uint8 systemRatio = _getSystemRatio((start_state.totalActiveSize + end_state.totalActiveSize)/2);
        //计算处理guaranteeRatio为标准倍数（1倍），实现基本的占比逻辑 ratio_a = a / a + b*g;ration_b = b*g / (a+b*g)
        //(supply_rate * order_.guaranteeRatio) / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 supplierReward = ((((reward*systemRatio)>>8)* uint256(supplyRatio) * uint256(order_.guaranteeRatio))>>4) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);
        //daemon_rate / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 buyerReward = (((reward*systemRatio)>>8) * uint256(demandRatio)) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);

        _mintGWT(reward,address(this));
        gwtToken.transferFrom(address(this), supplier_.cfo, supplierIncome + supplierReward);
        gwtToken.transferFrom(address(this), usage_.buyer, buyerReward  + depositAmount);
    }

    //end & withdraw:  供应商主动说明数据丢失,DONE
    function reportDataLost(uint64 orderId, bytes32 rootHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId == 0, "Only demand order can be challenged");

        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        require(_isValidOperator(supplier_,msg.sender), "Only operator can report data lost");

        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(usage_.challengeHash == 0, "Challenge Already initiated");

        usage_.status = UsageStatus.Lost;
        //usage_.endPeriod = currentPeriod;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage_.size;
        order_.remainingSize += (usage_.size / 10);//返还10%的保证金
        
        //以当前时间为结束时间计算算力奖励
        //buyer:支付当前时间以前的费用，获得90%保证金和诉讼费
        //supplier:获得当前时间以前的费用。
        uint64 startPeriod = usage_.lastWithDrawPeriod == 0?usage_.activePeriod:usage_.lastWithDrawPeriod;
        SystemState storage end_state = all_system_states[currentPeriod];
        SystemState storage start_state = all_system_states[startPeriod];
        //供应商提取的是1）buyer按比例的费用 2)算力奖励
        //buyer提取的是：算力奖励
        uint256 supplierIncome =  _calcTotalPrice(currentPeriod - startPeriod, order_.price, usage_.size);
        uint256 depositAmount = _calcDeposit(_calcTotalPrice(currentPeriod - usage_.activePeriod,order_.price,usage_.size),order_.guaranteeRatio);
        uint256 reward = _calcReward(currentPeriod - startPeriod, usage_.size,order_.price,order_.guaranteeRatio,start_state,end_state);
        
        //supplyRatio:16为1倍，最大值为 256 (16倍)
        uint32 supplyRatio = uint32(end_state.supplyRatio + start_state.supplyRatio) / 2;
        uint32 demandRatio = uint32(end_state.demandRatio + start_state.demandRatio) / 2;
        
        uint8 systemRatio = _getSystemRatio((start_state.totalActiveSize + end_state.totalActiveSize)/2);
        //计算处理guaranteeRatio为标准倍数（1倍），实现基本的占比逻辑 ratio_a = a / a + b*g;ration_b = b*g / (a+b*g)
        //(supply_rate * order_.guaranteeRatio) / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 supplierReward = ((((reward*systemRatio)>>8)* uint256(supplyRatio) * uint256(order_.guaranteeRatio))>>4) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);
        //daemon_rate / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 buyerReward = (((reward*systemRatio)>>8) * uint256(demandRatio)) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);

        _mintGWT(reward,address(this));
        gwtToken.transferFrom(address(this), supplier_.cfo, supplierIncome + supplierReward);
        gwtToken.transferFrom(address(this), usage_.buyer, buyerReward + (depositAmount*9)/10);

    }

    //认为挑战设置的challengeHash并不是roothash的Merkle叶子节点
    function declearChallengeIllegal(uint64 orderId, bytes32 rootHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId == 0, "Only demand order can be challenged");
        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(usage_.challengeHash != 0, "No challenge initiated");
        require(currentPeriod - usage_.challengePeriod <= sysChallengeTimeout, "Challenge expired");
        require(usage_.declearPeriod == 0, "Already decleared illegal");
        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        require(_isValidOperator(supplier_,msg.sender), "Only operator can declear Challenge Illegal");
   
        gwtToken.transferFrom(supplier_.cfo, address(this),sysDeclearFee);
        usage_.declearPeriod = currentPeriod;
    }

    //end & withdraw: 展示叶子节点的路径并验证,DONE
    function showChallengePath(uint64 orderId,bytes32 rootHash,uint64 dataIndex,bytes32[] calldata fullPath) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        require(order_.supplierId == 0, "Only demand order can be challenged");
        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(usage_.challengeHash != 0, "No challenge initiated");
        require(usage_.declearPeriod != 0, "No decleared illegal");
        if(currentPeriod - usage_.challengePeriod > sysChallengeTimeout) {
            usage_.declearPeriod = 0;
            usage_.challengeHash = 0;
            return;
        }

        require(verify(fullPath,rootHash,usage_.challengeHash,dataIndex),"Show evidence failed");

        usage_.status = UsageStatus.ChallengeSuccess;
        usage_.endPeriod = currentPeriod;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage_.size;
        //order_.remainingSize += usage_.size; 数据损坏会导致订单的总大小无法恢复，进而导致supplier无法通过释放空间逻辑得到保证金
        
        //以挑战时间为结束时间计算算力奖励
        //buyer:支付挑战时间以前的费用，获得保证金和诉讼费用（手续费补贴）
        //supplier:获得支付挑战时间以前的费用。
        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        uint64 startPeriod = usage_.lastWithDrawPeriod == 0?usage_.activePeriod:usage_.lastWithDrawPeriod;
        SystemState storage end_state = all_system_states[usage_.challengePeriod];
        SystemState storage start_state = all_system_states[startPeriod];
        //供应商提取的是1）buyer按比例的费用 2)算力奖励
        //buyer提取的是：算力奖励
        uint256 supplierIncome =  _calcTotalPrice(usage_.challengePeriod - startPeriod, order_.price, usage_.size);
        uint256 depositAmount = _calcDeposit(_calcTotalPrice(usage_.effectivePeriod - usage_.activePeriod,order_.price,usage_.size),order_.guaranteeRatio);
        uint256 reward = _calcReward(usage_.challengePeriod - startPeriod, usage_.size,order_.price,order_.guaranteeRatio,start_state,end_state);
        
        //supplyRatio:16为1倍，最大值为 256 (16倍)
        uint32 supplyRatio = uint32(end_state.supplyRatio + start_state.supplyRatio) / 2;
        uint32 demandRatio = uint32(end_state.demandRatio + start_state.demandRatio) / 2;
       
        uint8 systemRatio = _getSystemRatio((start_state.totalActiveSize + end_state.totalActiveSize)/2);
        //计算处理guaranteeRatio为标准倍数（1倍），实现基本的占比逻辑 ratio_a = a / a + b*g;ration_b = b*g / (a+b*g)
        //(supply_rate * order_.guaranteeRatio) / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 supplierReward = ((((reward*systemRatio)>>8)* uint256(supplyRatio) * uint256(order_.guaranteeRatio))>>4) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);
        //daemon_rate / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 buyerReward = (((reward*systemRatio)>>8) * uint256(demandRatio)) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);

        _mintGWT(reward,address(this));
        gwtToken.transferFrom(address(this), supplier_.cfo, supplierIncome + supplierReward);
        gwtToken.transferFrom(address(this), usage_.buyer, buyerReward + sysDeclearFee + depositAmount);
        
    }

    //TODO 需要确保该实现与DMC Mainchain的一致
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf, uint index) public pure returns (bool) {
        bytes32 hash = leaf;
        for (uint i = 0; i < proof.length; i++) {
            if (index % 2 == 0) {
                hash = keccak256(abi.encodePacked(hash, proof[i]));
            } else {
                hash = keccak256(abi.encodePacked(proof[i], hash));
            }
            index = index / 2;
        }

        return hash == root;
    }
    
    function leave(uint64 orderId,uint64 supplierId ) public {
        updateComputeState();
        require(supplierId != 0, "Only supplier can leave");

        StorageOrder storage order_ = orders[orderId];
        StorageSupplier storage supplier_ = all_suppliers[supplierId];
       
        require(order_.status == OrderStatus.Active, "Order not active");
        //TODO 总次数应该和Order的总时长，以及quality参数有关
        require(order_.leaveCount < sysMaxLeaveCount, "Leave too frequent");
        require(currentPeriod - order_.leavePeriod > sysMinLeaveDuration, "Leave too frequent");
        require(order_.effectivePeriod - currentPeriod > sysMinLeaveDuration, "Order too close to end");
        require(_isValidOperator(supplier_,msg.sender), "Only operator can leave");
       
        order_.status = OrderStatus.OnLeave;     
        order_.leavePeriod = currentPeriod;   
        order_.leaveCount ++;
    }

    function resumeFromLeave(uint64 orderId,uint64 supplierId) public {
        updateComputeState();
        require(supplierId != 0, "Only supplier can leave");

        StorageOrder storage order_ = orders[orderId];
        StorageSupplier storage supplier_ = all_suppliers[supplierId];

        require(order_.status == OrderStatus.OnLeave, "Order not on leave");
        require(_isValidOperator(supplier_,msg.sender), "Only operator can leave");

        order_.status = OrderStatus.Active;
    }

    //活动订单中途提现 （必须是active）,DONE
    function withDraw(uint64 orderId, bytes32 rootHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(usage_.effectivePeriod > currentPeriod, "Usage already ended");
        require(usage_.challengeHash == 0, "Challenge Already initiated");

        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        uint64 startPeriod = usage_.lastWithDrawPeriod == 0?usage_.activePeriod:usage_.lastWithDrawPeriod;
        SystemState storage end_state = all_system_states[currentPeriod];
        SystemState storage start_state = all_system_states[startPeriod];
        //供应商提取的是1）buyer按比例的费用 2)算力奖励
        //buyer提取的是：算力奖励
        uint256 supplierIncome =  _calcTotalPrice(currentPeriod - startPeriod, order_.price, usage_.size);
        uint256 reward = _calcReward(currentPeriod - startPeriod, usage_.size,order_.price,order_.guaranteeRatio,start_state,end_state);
        
        //supplyRatio:16为1倍，最大值为 256 (16倍)
        uint32 supplyRatio = uint32(end_state.supplyRatio + start_state.supplyRatio) / 2;
        uint32 demandRatio = uint32(end_state.demandRatio + start_state.demandRatio) / 2;

        uint8 systemRatio = _getSystemRatio((start_state.totalActiveSize + end_state.totalActiveSize)/2);
        //计算处理guaranteeRatio为标准倍数（1倍），实现基本的占比逻辑 ratio_a = a / a + b*g;ration_b = b*g / (a+b*g)
        //(supply_rate * order_.guaranteeRatio) / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 supplierReward = ((((reward*systemRatio)>>8)* uint256(supplyRatio) * uint256(order_.guaranteeRatio))>>4) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);
        //daemon_rate / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 buyerReward = (((reward*systemRatio)>>8) * uint256(demandRatio)) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);

        _mintGWT(reward,address(this));
        gwtToken.transferFrom(address(this), supplier_.cfo, supplierIncome + supplierReward);
        gwtToken.transferFrom(address(this), usage_.buyer, buyerReward);

        usage_.lastWithDrawPeriod = currentPeriod;
    }

    //end & withdraw,订单到期正常结束,调用会触发提现,DONE
    function endUsage(uint64 orderId, bytes32 rootHash) public {
        updateComputeState();
        StorageOrder storage order_ = orders[orderId];
        StorageUsage storage usage_ = all_usage[rootHash];
        require(usage_.orderId == orderId, "orderid not match");
        require(usage_.status == UsageStatus.Active, "Usage not active");
        require(currentPeriod >  usage_.effectivePeriod, "Usage not end");
        require(usage_.challengeHash == 0, "Challenge Already initiated");
        
        usage_.status = UsageStatus.Ended;
        order_.remainingSize += usage_.size;
        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage_.size;
        
        StorageSupplier storage supplier_ = all_suppliers[order_.supplierId];
        uint64 startPeriod = usage_.lastWithDrawPeriod == 0?usage_.activePeriod:usage_.lastWithDrawPeriod;
        SystemState storage end_state = all_system_states[usage_.effectivePeriod];
        SystemState storage start_state = all_system_states[startPeriod];
  
        uint256 supplierIncome =  _calcTotalPrice(usage_.effectivePeriod - startPeriod, order_.price, usage_.size);
        uint256 reward = _calcReward(usage_.effectivePeriod - startPeriod, usage_.size,order_.price,order_.guaranteeRatio,start_state,end_state);
        
        //supplyRatio:16为1倍，最大值为 256 (16倍)
        uint32 supplyRatio = uint32(end_state.supplyRatio + start_state.supplyRatio) / 2;
        uint32 demandRatio = uint32(end_state.demandRatio + start_state.demandRatio) / 2;
        
        uint8 systemRatio = _getSystemRatio((start_state.totalActiveSize + end_state.totalActiveSize)/2);
        //计算处理guaranteeRatio为标准倍数（1倍），实现基本的占比逻辑 ratio_a = a / a + b*g;ration_b = b*g / (a+b*g)
        //(supply_rate * order_.guaranteeRatio) / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 supplierReward = ((((reward*systemRatio)>>8)* uint256(supplyRatio) * uint256(order_.guaranteeRatio))>>4) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);
        //daemon_rate / (daemon_rate + supply_rate*order_.guaranteeRatio)
        uint256 buyerReward = (((reward*systemRatio)>>8) * uint256(demandRatio)) / (uint256(demandRatio) + uint256(supplyRatio) * uint256(order_.guaranteeRatio)>>4);

        _mintGWT(reward,address(this));
        gwtToken.transferFrom(address(this), supplier_.cfo, supplierIncome + supplierReward);
        gwtToken.transferFrom(address(this), usage_.buyer, buyerReward);
    }
    

    // 更新算力奖励
    function updateComputeState() public {
        SystemState storage state = all_system_states[currentPeriod];
        //判断是否可以结束当前period
        if(block.number - state.blockNumber <= sysBlockPerPeriod) {
            return;
        }
        SystemState storage lastState = all_system_states[currentPeriod-1]; //合约初始化的时候要初始化一个初始的计算状态，为各个经济学参数赋予初值

        if(state.totalActiveSize > lastState.totalActiveSize) {
            //计算 6周预期的增长数值growth 
            uint128 growth = (state.totalActiveSize - lastState.totalActiveSize)*56*6;
            //计算 rate = (growth / last_state.totalActiveSize) / 25% =  (growth*4 / last_state.totalActiveSize) ; 
            // 用 0-2^16 的整数代替浮点数，因此  rate = (growth*4 / last_state.totalActiveSize) * (2^15)
            state.rewardRate  = uint16((growth<<17) / lastState.totalActiveSize);
        } else {
            //存储空间下降，取最低值（TODO：计算下降比率，然后用lastState.rewardRate*下降比率）
            //  上述算法的主要问题是，有可能下降 还要比 增长 慢的效果更好。
            state.rewardRate = 1638;//(0.05 * 2^15)
        }

        //计算supplyRatio和demandRatio
        if(state.totalSupplyOrderSize > state.totalDemandOrderSize) {
            state.demandRatio = 1<<4;
            if(state.totalSupplyOrderSize*256<state.totalActiveSize) {
                state.supplyRatio = 1<<4;
            } else {
                state.supplyRatio = uint8(state.totalActiveSize<<4 / state.totalSupplyOrderSize);
            }
        } else {
            state.supplyRatio = 1<<4;
            if(state.totalDemandOrderSize*256<state.totalActiveSize) {
                state.demandRatio = 1<<4;
            } else {
                state.demandRatio = uint8(state.totalDemandOrderSize<<4 / state.totalSupplyOrderSize);
            }
        }

        //挂单奖励是根据rewardRate,suplyRation,demandRation计算，这里不用更新
        SystemState memory newState = state;
        newState.blockNumber = block.number;//TODO:还是应该用  lastState.blockNumber + sysBlockPerPeriod?
        // 要不要考虑一段时间内，没有任何交易的情况？可能会跳周期
        // 先做一个跳周期的逻辑，让测试可以跑过
        // 真实系统中，第一个卖单和买单也可能出现不跳周期不能成交的情况
        uint64 skipPeriod = uint64((block.number - all_system_states[0].blockNumber) / sysBlockPerPeriod);
        // 不知道这里用一个ceil()逻辑对不对......
        if (sysBlockPerPeriod * skipPeriod < block.number - all_system_states[0].blockNumber) {
            skipPeriod++;
        }
        currentPeriod = currentPeriod + skipPeriod;
        all_system_states[currentPeriod] = newState;
    }


    // TODO:兑换DMC和GWT (可以用DeFi逻辑实现和任意Token的兑换？)
    //function exchangeDMCforGWT(uint256 dmcAmount) public {
       // require(dmcToken.balanceOf(msg.sender) >= dmcAmount, "Insufficient DMC balance");
        // 兑换逻辑，涉及市场价格、兑换率等

        //emit DMCExchangedForGWT(msg.sender, dmcAmount, gwtAmount);
    //}

    //function exchangeGWTforDMC(uint256 gwtAmount) public {
        //require(gwtToken.balanceOf(msg.sender) >= gwtAmount, "Insufficient GWT balance");
        // 兑换逻辑，涉及市场价格、兑换率等

        //emit GWTExchangedForDMC(msg.sender, gwtAmount, dmcAmount);
    //}

    //LP逻辑

    //系统LP，绑定一种DAOToken，用于分红，分红的收入来源是系统的tax,包括GWT和内置交易所的收入
    //基本思路： 质押DAOToken，参与下一个分红周期的分红（8周分红一次）
    //分红逻辑：每个周期，系统会计算所有LP的总质押量，然后按照质押量比例分配分红，LP可以随时提取自己归属的分红，但提取DAO Token后，会至少miss一个周期的分红

    // 暂停和恢复合约操作，作为紧急措施
    //function pauseContract() public onlyOwner {
    //    // 实现合约暂停逻辑
    //}

    //function resumeContract() public onlyOwner {
    //    // 实现合约恢复逻辑
    //}

}
