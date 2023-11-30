// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./pst.sol";


contract StorageExchange {
    PSTToken public pstToken;

    struct StorageSupplier {
        address ceo;//可以修改地址
        address cfo;//可以提现，挂单
        address[] operators; //不可以进行金融操作
        string[] urlprefixs; //可以修改 比如 https://www.hostname.com/get/
        address[] LPs;//其它股东
    }
    
    enum UsageStatus {Waiting, Active, ChallengeSuccess, Cancelled,Ended,CancelledFromWait,Lost}
    struct StorageUsage {
        address buyer;
        uint64 size;
        UsageStatus status;
        uint64 craetePeriod;//创建时间
        uint64 effectivePeriod;//计划结束时间,TODO:简单实现可以和order的effectivePeriod一致
        uint64 activePeriod; //变成激活状态的时间
        uint64 endPeriod;//从激活变成非激活状态的时间
        
        bytes32 challengeHash;
        uint64 challengePeriod;
        uint64 declearPeriod;
        uint64 lastWithDrawPeriod;

    }

    enum OrderStatus {Waiting,  Active, OnLeave, Cancelled , Ended}
    struct StorageOrder {
        uint64 size;
        uint16 quality;// 年故障率（不允许填0），这个值越大，越有概率系统返还保证金。
        uint16 pricePerPST;//单位是128的倍数。最小值为 16 (12.5%) 最大值为 1024 (8倍)
        uint8 guaranteeRatio;//质押率，单位是16的倍数。最小值为 8（0.5倍），最大值为 256 (16倍)
        uint createPeriod; //创建时的周期编号
        uint64 effectivePeriod;//结束时的周期编号

        uint32 minimumPurchaseSize;
        uint256 depositAmount;//TODO：可以废弃？

        uint64 supplierId;
        OrderStatus status;
        uint64 remainingSize;
        uint64 leavePeriod;//如果当前处于请假状态，本次请假的区块高度
        uint8 leaveCount;//已经请假的总次数
        
        mapping(bytes32 => StorageUsage) buyers; 
    }

    
    struct SystemState {
        uint64 blockNumber;//本周期的开始区块高度
        uint128 totalActiveSize;
        uint128 totalSupplyOrderSize;
        uint128 totalDemandOrderSize;

        /**
         * @notice 
         * 
         * 基本思路： 调整Ratio平衡供求关系
         * 基于算力增发PST的目标是：让PST的总流通量是系统可用存储总量的 约10倍。其参数设计参考宏观经济学的货币发行总量、GDP、平均周转周期逻辑
         * 如果没有其它的因素，所有的 存储交易都是在得到PST后立刻扩产，2年后，系统产出的PST总量是系统总量的约5倍
         * 
         * 每6周，大概会奖励释放6周总价25%的PST, 根据预期增长率，和自己的价格曲线，最多可以达到 50%总算力，最低保底由当前总算力决定，
         * 保底增长率  16PB  256PB 1EB  4EB  8EB 16EB 32EB     256EB  512EB  1ZB 以上  
         *            25    20    15   10   5   4    3    2   1      0.5     0
         * 实际增长率 d
         * 根据当前总算力计算出的增长率 r = 25% 
         * 
         * 刚刚开始的周期称作本周期
         * 
         * 本周期的总有效算力 如果 比上个周期的总有效算力提升，则系统应增发更多的PST，如果有效算力下降，应该增发更少的PST
         * 
         */

        uint8 supplyRatio; //16为1倍，最大值为 256 (16倍)
        uint8 demandRatio; //16为1倍，最大值为 256 (16倍)
        uint16 systemRatio; //计算算力奖励时，给到系统的比例
        uint16 rewardRate;//算力奖励的比例.取值为其浮点数 *256
        uint16 taxRate;//交易结算时，给到系统的交易费用比例
        
        //uint16 avgPricePerPST; 简化实现，强调1PST就是平均价格
    }


    uint64 public nextOrderId = 0;
    mapping(uint64 => StorageOrder) public orders;
    
    mapping(uint64 => StorageSupplier) public all_suppliers;
    uint64 public nextSupplierId = 1;

    mapping(uint64 => SystemState) public all_system_states;
    uint64 public currentPeriod = 0;

    uint256 public sysPSTAmount = 0;


    uint16 public sysMinPrice = 16; //最小价格，单位是128的倍数。最小值为 16 (12.5%) 最大值为 1024 (8倍)
    uint8 public sysMinGuaranteeRatio = 8; //最小质押率，单位是16的倍数。最小值为 8（0.5倍），最大值为 256

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
    

    constructor(address _pstTokenAddress) {
        pstToken = PSTToken(_pstTokenAddress);
        nextOrderId = 0;

        //为了减少除零风险，系统初始化时有1TB的算力，供需双方各10GB的挂单算力，并且已经有了2个已知的系统状态

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

    //结算周期，1天8次，每次约3小时，一个Week等于56个peroid
    function _getSettlementPeriod(uint64 blockNunmberDistance) private view returns (uint64) {
        return blockNunmberDistance / sysBlockPerPeriod;
    }

    function _getBlockNumbDistanceFromPeriodCount(uint64 currentPeriodStartBlockNumber,uint64 periodCount) private view returns (uint64) {
        return currentPeriodStartBlockNumber + periodCount * sysBlockPerPeriod;
    }

    function _calcTotalPrice(uint64 periodCount,uint16 pricePerPST,uint64 size) private view returns (uint256) {
        uint weekCount = periodCount / 56;
        //pricePerPST的单位是用uint16标示的标准倍数，其中 128为1倍，系统最小值为16，最大值为 1024
        return (weekCount * pricePerPST * size)>>7;
    }

    function _calcDeposit(uint256 totalPrice,uint8 guaranteeRatio) private view returns (uint256) {
        return (totalPrice * guaranteeRatio)>>4;
    }



    function _isValidOperator(StorageSupplier storage supplier, address operator) private view returns (bool) {
        for (uint i = 0; i < supplier.operators.length; i++) {
            if (supplier.operators[i] == operator) {
                return true;
            }
        }
        return false;
    }

    function _mintPST(uint256 amount,address target) private {
        //TODO
    }

    function createSupplier(address cfo,address[] calldata operators, string[] calldata urlprefixs) public returns (uint64) {
        all_suppliers[nextSupplierId] = StorageSupplier(msg.sender,cfo,operators,urlprefixs,new address[](0));
        nextSupplierId++;
        return nextSupplierId-1;
    }

    function udpateSupplier(uint64 supplierId,address cfo,address[] calldata operators, string[] calldata urlprefixs) public {
        StorageSupplier storage supplier = all_suppliers[supplierId];
        require(msg.sender == supplier.ceo, "Only ceo can update supply info");
        supplier.cfo = cfo;
        supplier.urlprefixs = urlprefixs;
        supplier.operators = operators;
    }

    //创建订单，大部分情况是供应单，也可以是需求单
    function createStorageOrder(uint64 supplierId, uint64 size, uint16 quality, uint16 pricePerPST, uint64 effectivePeriod, uint32 minimumPurchaseSize,
                                uint256 depositAmount, bytes32 rootHash) public {
        require(effectivePeriod >= sysMinEffectivePeriod, "Effective time too short");
        require(pricePerPST >= sysMinPrice, "Price too low");
        uint256 totalPrice = _calcTotalPrice(effectivePeriod, pricePerPST,size);
        uint8 guaranteeRatio = uint8((depositAmount*16) / totalPrice);
        require(depositAmount >= (totalPrice * sysMinGuaranteeRatio)>>4, "Deposit amount too small");
        
        if(supplierId != 0) {
            StorageSupplier storage supplier = all_suppliers[supplierId];
            require(_isValidOperator(supplier, msg.sender), "Only operator can create order");
            require(minimumPurchaseSize >= sysMinPurchaseSize, "Minimum purchase size too small");
            
            pstToken.transferFrom(supplier.cfo, address(this), depositAmount);
        } else {
            require(size >= sysMinDemandSize);
            require(minimumPurchaseSize == size);
            //需求方依旧可以通过depositAmount要求质押率
            pstToken.transferFrom(msg.sender, address(this), totalPrice);
        }

        SystemState storage state = all_system_states[currentPeriod];

        StorageOrder storage order = orders[nextOrderId];
        order.size = size;
        order.quality = quality;
        order.pricePerPST = pricePerPST;
        order.guaranteeRatio = guaranteeRatio;
        order.createPeriod = currentPeriod;
        order.effectivePeriod = effectivePeriod;
        order.minimumPurchaseSize = minimumPurchaseSize;
        order.depositAmount = depositAmount;
        order.status = OrderStatus.Waiting;
        order.remainingSize = size;
        order.leaveCount = 0;
        order.leavePeriod = 0;

        if(supplierId != 0) {
            order.supplierId = supplierId;
            state.totalSupplyOrderSize += size; 
        }else{
            order.supplierId = 0;

            order.buyers[rootHash] = StorageUsage(msg.sender,
                size,
                UsageStatus.Waiting,
                currentPeriod,
                effectivePeriod,
                0,
                0,
                0,
                0,
                0,
                0);

            state.totalDemandOrderSize += size;
        }

        nextOrderId++;
    }



    //向一个订单购买存储空间
    function buyStorage(uint64 orderId, uint64 size,bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.size == 0, "Already bought");
        require(order.status == OrderStatus.Waiting || order.status == OrderStatus.Active, "Only waiting or active order can be bought");
        require(order.remainingSize >= size, "Not enough storage available");
        require(size >= order.minimumPurchaseSize, "size too small");
        //还有足够的有效期,TODO所有处理有效期为周的地方都要检查
        require(order.effectivePeriod - currentPeriod >= sysMinEffectivePeriod, "Not enough effective time");
        //只有订单创建开始一小段时间后，才能购买
        require(currentPeriod - order.createPeriod > sysMinActivePeriod, "wait order active");
       
       
        uint256 totalPrice = _calcTotalPrice(order.effectivePeriod - currentPeriod, order.pricePerPST, size);
        pstToken.transferFrom(msg.sender, address(this), totalPrice);
        
        SystemState storage state = all_system_states[currentPeriod];
        usage.buyer = msg.sender;
        usage.craetePeriod = currentPeriod;
        usage.effectivePeriod = order.effectivePeriod;
        usage.status = UsageStatus.Waiting;

        order.status = OrderStatus.Active;
        order.remainingSize -= size;
        state.totalSupplyOrderSize -= size;
        //emit StoragePurchased(orderId, msg.sender, size);
    }

    //向一个订单发送报价意向
    function makeOffer(uint64 supplierId,uint64 orderId) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId == 0, "Only demand orders can receive offers");
        require(order.status == OrderStatus.Waiting, "Only waiting order can receive offers");
        //只有订单创建开始一小段时间后，才能报价
        require(currentPeriod - order.createPeriod > sysMinActivePeriod, "wait order active");
        require(order.effectivePeriod - currentPeriod <= sysMinEffectivePeriod, "wait order active");
        StorageSupplier storage supplier = all_suppliers[supplierId];
        require(_isValidOperator(supplier,msg.sender), "Only operator can make offer");

        pstToken.transferFrom(supplier.cfo, address(this), order.depositAmount);
        order.supplierId = supplierId;
        order.status = OrderStatus.Active;
        order.createPeriod = currentPeriod - 2;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalDemandOrderSize -= order.size;
    } 

    // 取消订单
    // TODO:已经事实上没有usage的订单是否可以取消？这里的计算有点复杂
    function cancelOrder(uint64 orderId) public {
        StorageOrder storage order = orders[orderId];
        require((order.supplierId !=0), "Only standard order can be cancelled");

        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        require(_isValidOperator(supplier,msg.sender), "Only operator can cancelOrder");
        require(order.status == OrderStatus.Waiting, "Only waiting order can be cancelled");

        pstToken.transferFrom(address(this), supplier.cfo, order.depositAmount);
        order.status = OrderStatus.Cancelled;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalSupplyOrderSize -= order.size;
 
        //emit OrderCancelled(orderId);
    }

    function confirmUsageRoot(uint64 orderId,bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        StorageUsage storage usage = order.buyers[rootHash];

        require(usage.buyer != address(0), "No such rootHash");
        require(usage.status == UsageStatus.Waiting, "Already confirmed");
        require(_isValidOperator(supplier,msg.sender), "Only operator can confirm usage");

        usage.status = UsageStatus.Active;
        usage.activePeriod = currentPeriod;
        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize += usage.size;
    }

    //TODO：双方主动协商，友好提前结束订单
    function cancelUsage(uint64 orderId,bytes32 rootHash) public {

    }


    // 发起存储挑战
    function challenge(uint64 orderId,bytes32 rootHash, bytes32 challengeHash) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId != 0, "Only standard order can be challenged");
        
        if(order.status == OrderStatus.OnLeave) {
            if(currentPeriod - order.leavePeriod > sysMinLeaveDuration) {
                order.status = OrderStatus.Active;
                order.leavePeriod = 0;
            }
        } else {
            require(order.status == OrderStatus.Active, "Order not active");
        }
        
        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.declearPeriod == 0, "Already decleared challenge illegal");
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(currentPeriod - usage.challengePeriod > sysMinChallengeDuration, "Challenge too frequent");

        usage.challengeHash = challengeHash;
        usage.challengePeriod = currentPeriod;
    }

    // 响应简单挑战
    function respondChallenge(uint64 orderId, bytes32 rootHash,bytes calldata rawData) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId == 0, "Only demand order can be challenged");

        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(usage.challengeHash != 0, "No challenge initiated");
        require(currentPeriod - usage.challengePeriod <= sysChallengeTimeout, "Challenge expired");

        bytes32 responseHash = keccak256(rawData);
        require(responseHash == usage.challengeHash, "Respond Challenge failed");
        usage.challengeHash = 0;
    }

    //超时后，确认挑战成功，并提款
    function challengeSuccess(uint64 orderId, bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId == 0, "Only demand order can be challenged");

        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(usage.challengeHash != 0, "No challenge initiated");
        require(currentPeriod - usage.challengePeriod > sysChallengeTimeout, "Challenge is not expired!");

        usage.status = UsageStatus.ChallengeSuccess;
        usage.endPeriod = usage.challengePeriod  + sysChallengeTimeout;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage.size;

        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        _withdrawUsage(supplier,order,usage);
    }

    //供应商主动说明数据丢失
    function reportDataLost(uint64 orderId, bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId == 0, "Only demand order can be challenged");

        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        require(_isValidOperator(supplier,msg.sender), "Only operator can report data lost");

        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(usage.challengeHash == 0, "Challenge Already initiated");

        usage.status = UsageStatus.Lost;
        usage.endPeriod = currentPeriod;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage.size;

        _withdrawUsage(supplier,order,usage);
    }

    //认为挑战设置的challengeHash并不是roothash的Merkle叶子节点
    function declearChallengeIllegal(uint64 orderId, bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId == 0, "Only demand order can be challenged");
        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(usage.challengeHash != 0, "No challenge initiated");
        require(currentPeriod - usage.challengePeriod <= sysChallengeTimeout, "Challenge expired");
        require(usage.declearPeriod == 0, "Already decleared illegal");
        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        require(_isValidOperator(supplier,msg.sender), "Only operator can declear Challenge Illegal");
        //TODO:诉讼费用如何计算
        pstToken.transferFrom(supplier.cfo, address(this),sysDeclearFee);
        usage.declearPeriod = currentPeriod;
       
    }

    //展示叶子节点的路径并验证
    function showChallengePath(uint64 orderId,bytes32 rootHash,uint64 dataIndex,bytes32[] calldata fullPath) public {
        StorageOrder storage order = orders[orderId];
        require(order.supplierId == 0, "Only demand order can be challenged");
        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(usage.challengeHash != 0, "No challenge initiated");
        require(usage.declearPeriod != 0, "No decleared illegal");
        require(currentPeriod - usage.declearPeriod <= sysChallengeTimeout, "Show evidence to decleared Challenge illegal expired");

        require(verify(fullPath,rootHash,usage.challengeHash,dataIndex),"Show evidence failed");

        usage.status = UsageStatus.ChallengeSuccess;
        usage.endPeriod = currentPeriod;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage.size;
        
        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        _withdrawUsage(supplier,order,usage);
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
        require(supplierId != 0, "Only supplier can leave");

        StorageOrder storage order = orders[orderId];
        StorageSupplier storage supplier = all_suppliers[supplierId];
       
        require(order.status == OrderStatus.Active, "Order not active");
        //TODO 总次数应该和Order的总时长，以及quality参数有关
        require(order.leaveCount < sysMaxLeaveCount, "Leave too frequent");
        require(currentPeriod - order.leavePeriod > sysMinLeaveDuration, "Leave too frequent");
        require(order.effectivePeriod - currentPeriod > sysMinLeaveDuration, "Order too close to end");
        require(_isValidOperator(supplier,msg.sender), "Only operator can leave");
       
        order.status = OrderStatus.OnLeave;     
        order.leavePeriod = currentPeriod;   
        order.leaveCount ++;
    }

    function resumeFromLeave(uint64 orderId,uint64 supplierId) public {
        require(supplierId != 0, "Only supplier can leave");

        StorageOrder storage order = orders[orderId];
        StorageSupplier storage supplier = all_suppliers[supplierId];

        require(order.status == OrderStatus.OnLeave, "Order not on leave");
        require(_isValidOperator(supplier,msg.sender), "Only operator can leave");

        order.status = OrderStatus.Active;
    }

    //订单到期正常结束
    function endUsage(uint64 orderId, bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        require(currentPeriod >=  usage.effectivePeriod, "Usage not end");

        usage.endPeriod = usage.effectivePeriod;
        usage.status = UsageStatus.Ended;

        SystemState storage state = all_system_states[currentPeriod];
        state.totalActiveSize -= usage.size;

        StorageSupplier storage supplier = all_suppliers[order.supplierId];
        _withdrawUsage(supplier,order,usage);
    }

    //活动订单中途提现
    function withDraw(uint64 orderId, bytes32 rootHash) public {
        StorageOrder storage order = orders[orderId];
        StorageUsage storage usage = order.buyers[rootHash];
        require(usage.status == UsageStatus.Active, "Usage not active");
        StorageSupplier storage supplier = all_suppliers[order.supplierId];

        _withdrawUsage(supplier,order,usage);
    }

    function _withdrawUsage(StorageSupplier storage supplier,StorageOrder storage order,StorageUsage storage usage) private {
        uint64 startPeriod = usage.lastWithDrawPeriod;
        if(startPeriod == 0) {
            require(currentPeriod - usage.craetePeriod >= sysFirstWithDrawPeriod, "first withdraw must be after 6 weeks");
            startPeriod = usage.activePeriod;
        }
    
        SystemState storage start_state = all_system_states[startPeriod];
        if(usage.status == UsageStatus.Ended) {
            uint64 endPeriod = usage.endPeriod;
            if(startPeriod == endPeriod) {
                return;
            }

            SystemState storage end_state = all_system_states[endPeriod];
            //供应商提取的是1）buyer按比例的费用 2)算力奖励 3)保证金
            //buyer提取的是：算力奖励
            uint256 supplierIncome = _calcTotalPrice(endPeriod - startPeriod, order.pricePerPST, usage.size);
            uint256 supplierDeposit = _calcDeposit(supplierIncome,order.guaranteeRatio);

            uint16 startRewardRate = (order.pricePerPST * order.guaranteeRatio * start_state.rewardRate) >> 11;
            startRewardRate = getRateByCave(startRewardRate, start_state.totalActiveSize);
            uint16 endRewardRate = (order.pricePerPST * order.guaranteeRatio * end_state.rewardRate) >> 11;
            endRewardRate = getRateByCave(endRewardRate, end_state.totalActiveSize);
            uint16 rewardRaete = (startRewardRate + endRewardRate) / 2;
            
            //总奖励金额 = size*周期数*rewardRate
            uint256 rewardSize = (usage.size * rewardRaete * (usage.endPeriod - startPeriod)<<8) / 336;
            uint256 systemReward = rewardSize * end_state.systemRatio;
            rewardSize -= systemReward; 
            uint totalRatio = ((end_state.supplyRatio + start_state.supplyRatio)*order.guaranteeRatio)>>4 + end_state.demandRatio + start_state.demandRatio;
            uint256 supplierReward = (rewardSize * (end_state.supplyRatio + start_state.supplyRatio)*order.guaranteeRatio)>>4 / totalRatio;
            uint256 buyerReward = (rewardSize * (end_state.demandRatio + start_state.demandRatio)) / totalRatio;

            _mintPST(rewardSize,address(this));
            pstToken.transferFrom(address(this), supplier.cfo, supplierIncome + supplierDeposit + supplierReward);
            pstToken.transferFrom(address(this), usage.buyer, buyerReward);
            usage.lastWithDrawPeriod = usage.endPeriod;
        }
    }

    //function fullyScanAndUpdateComputeState(uint16 length) public {
        // From the perspective of economics games, the owner of the order has the motivation to end the order as soon as possible and extract PST, so we assume that the end time of the order is updated in a timely manner
        // In order to appear a large number of expirations when this interface, this interface is designed. If the end of the order is updated in time, the calculation of the compassion reward will be inaccurate
    //}
    
    function getRateByCave(uint16 rate,uint128 totalSize) public view returns (uint16) {
        //TODO
        return rate;
    }
    // 更新算力奖励
    function updateComputeState(uint256 orderId) public {
        //判断距离上一次计算的时间是否超过一定的时间间隔

        //读取全局变量：当前挂单的两种算力，处于成交阶段的算力
        //读取上一次更新计算时的3个值
        //根据当前的3个值，计算变化趋势，更新经济学参数
        SystemState storage last_state = all_system_states[currentPeriod-1]; //合约初始化的时候要初始化一个初始的计算状态，为各个经济学参数赋予初值
        SystemState storage state = all_system_states[currentPeriod];
        
        //计算rewardRate
        if(state.totalActiveSize > last_state.totalActiveSize) {
            //1）计算 6周预期的增长数值growth 
            uint128 growth = (state.totalActiveSize - last_state.totalActiveSize)*56*6;
            //2) 计算 rate = (growth / last_state.totalActiveSize) / 25% =  (growth*4 / last_state.totalActiveSize) ; 
            // 用 0-256的整数代替浮点数，因此  rate = (growth*4 / last_state.totalActiveSize) * 256
            state.rewardRate  = uint16((growth<<10) / last_state.totalActiveSize);
            
        } else {
            state.rewardRate = getRateByCave(0,last_state.totalActiveSize);
        }

        //计算supplyRatio和demandRatio，systemRatio
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

        //挂单奖励在哪？

        //更新taxRate（只和总大小有关？）

        SystemState memory newState = state;
        currentPeriod ++;
        all_system_states[currentPeriod] = newState;
    }


    // TODO:兑换DMC和PST (可以用DeFi逻辑实现和任意Token的兑换？)
    function exchangeDMCforPST(uint256 dmcAmount) public {
       // require(dmcToken.balanceOf(msg.sender) >= dmcAmount, "Insufficient DMC balance");
        // 兑换逻辑，涉及市场价格、兑换率等

        //emit DMCExchangedForPST(msg.sender, dmcAmount, pstAmount);
    }

    function exchangePSTforDMC(uint256 pstAmount) public {
        //require(pstToken.balanceOf(msg.sender) >= pstAmount, "Insufficient PST balance");
        // 兑换逻辑，涉及市场价格、兑换率等

        //emit PSTExchangedForDMC(msg.sender, pstAmount, dmcAmount);
    }

    //LP逻辑

    //系统LP，绑定一种DAOToken，用于分红，分红的收入来源是系统的tax,包括PST和内置交易所的收入
    //基本思路： 质押DAOToken，参与下一个分红周期的分红（8周分红一次）
    //分红逻辑：每个周期，系统会计算所有LP的总质押量，然后按照质押量比例分配分红，LP可以随时提取自己归属的分红，但提取DAO Token后，会至少miss一个周期的分红

    // 暂停和恢复合约操作，作为紧急措施
    //function pauseContract() public onlyOwner {
    //    // 实现合约暂停逻辑
    //}

    //function resumeContract() public onlyOwner {
    //    // 实现合约恢复逻辑
    //}

    //event OrderCancelled(uint256 indexed orderId);
    //event StorageOrderCreated(uint256 indexed orderId);
    //event OrderFulfilled(uint256 indexed orderId, uint256 purchaseSize);
    //event MiningRewardsUpdated(uint256 indexed orderId, uint256 rewardAmount);
    //event MiningRewardCalculated(uint256 indexed orderId, uint256 reward);
    //event StorageChallengeInitiated(uint256 indexed orderId, bytes32 challengeHash);
    //event StorageChallengeResponded(uint256 indexed orderId, bytes32 responseHash);
    //event OrderLeaveApplied(uint256 indexed orderId);
    //event OrderResumedFromLeave(uint256 indexed orderId);
    //event DMCExchangedForPST(address indexed user, uint256 dmcAmount, uint256 pstAmount);
    //event PSTExchangedForDMC(address indexed user, uint256 pstAmount, uint256 dmcAmount);
    //event CollateralDeposited(uint256 indexed orderId, uint256 amount);
    //event CollateralRefunded(uint256 indexed orderId, uint256 amount);
    //event OrderStatusUpdated(uint256 indexed orderId, OrderStatus newStatus);
    //event OrderCreated(uint256 indexed orderId, address provider, uint256 size);
    //event OrderFulfilled(uint256 indexed orderId, address buyer, uint256 purchaseSize);
    //event OrderCancelled(uint256 indexed orderId, address provider);

}
