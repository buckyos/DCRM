import hre from "hardhat";
import { expect } from "chai";
import { StorageExchange, GWTToken } from "../typechain-types";
import { EventLog } from "ethers";
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { mine } from "@nomicfoundation/hardhat-network-helpers";

const sysPeriodPerWeek = 56; //一周是56个周期

// 测试ts里，token单位会转成有小数点的标准token单位，而不是最小单位。单位转换用10**18
const sysFixPeriodPerWeek = 56;

function _calcTotalPrice(periodCount: number, price: number,size: number): number {
    //price的单位是用uint16标示的标准倍数，其中 128为1倍，系统最小值为16，最大值为 1024
    // sysFixPeriodPerWeek = (10**18 / sysPeriodPerWeek)/128, 10**18是为了避免小数点,sysPeriodPerWeek=56
    // 这里得到的值是GWT Token的数量，带小数点
    return (periodCount * (price >> 7) * size) * sysFixPeriodPerWeek;
}

function _calcDeposit(totalPrice: number,guaranteeRatio: number):number {
    return (totalPrice * guaranteeRatio)>>4;
}

describe("StorageExchange", () => {
    let pstContract: GWTToken;
    let exchangeContract: StorageExchange;
    let signers: HardhatEthersSigner[];
    
    async function deployContracts() {
        pstContract = await (await hre.ethers.deployContract("GWTToken",[hre.ethers.parseEther("100000")])).waitForDeployment();

        let pstAddress = await pstContract.getAddress();
        const _exchangeContract = await (await hre.ethers.deployContract("StorageExchange", [pstAddress])).waitForDeployment();
        exchangeContract = _exchangeContract as StorageExchange;
        
        //return { pstContract, exchangeContract: exchangeContract as StorageExchange };
    }

    before(async () => {
        await deployContracts();
        // 给cfo signers[3].address分一些PST
        signers = await hre.ethers.getSigners();
        await (await pstContract.transfer(signers[3].address, hre.ethers.parseEther("10000"))).wait()
        // 给买家 signers[5].address分一些PST
        await (await pstContract.transfer(signers[5].address, hre.ethers.parseEther("10000"))).wait()
        console.log(`signers[3] ${signers[3].address} has balance ${await pstContract.balanceOf(signers[3].address)}`)
    });

    it("create supplier", async () => {
        //let { pstContract, exchangeContract } = await loadFixture(deployContracts);
        let signers = await hre.ethers.getSigners();
        let cfo = signers[1].address;
        let operator = signers[2].address;
        // how to convert longitude and latitude to uint32?
        let receipt = await (await exchangeContract.createSupplier(cfo, [operator], ["https://test.storage.suppily.com"], 100, 200)).wait();

        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have SupplierCreated event").is.equal("SupplierCreated");
        expect((receipt!.logs[0]! as EventLog).args[0], "supplier is shoule be 1").is.equal(1);

        let supplier = await exchangeContract.supplier((receipt!.logs[0]! as EventLog).args[0]);

        expect(supplier.cfo, "cfo is not correct").is.equal(cfo);
        expect(supplier.operators[0], "operator is not correct").is.equal(operator);
        expect(supplier.urlprefixs[0], "urlprefixs is not correct").is.equal("https://test.storage.suppily.com");
    });

    it("update supplier", async () => {
        let signers = await hre.ethers.getSigners();
        let receipt2 = await (await exchangeContract.updateSupplier(1, signers[3].address, [signers[4].address], ["https://test.storage.suppily2.com"])).wait();

        expect((receipt2!.logs[0]! as EventLog).eventName, "shoule have SupplierChanged event").is.equal("SupplierChanged");
        expect((receipt2!.logs[0]! as EventLog).args[0], "supplier id is shoule be 1").is.equal(1);

        let supplier = await exchangeContract.supplier(1);

        expect(supplier.cfo, "cfo is not correct").is.equal(signers[3].address);
        expect(supplier.operators[0], "operator is not correct").is.equal(signers[4].address);
        expect(supplier.urlprefixs[0], "urlprefixs is not correct").is.equal("https://test.storage.suppily2.com");
    });

    const valid_size = 1024*1024*1024*32;
    const valid_price = 16;// price取值为16~1024，表示0.125倍到8倍
    const valid_effective_period = 56*24;
    const valid_minimumPurchaseSize = 1024*1024*1024*2;
    const valid_guaranteeRatio = 8;//取值范围是8~256，表示0.5倍到16倍

    it("sell bill not operator", async () => {
        await expect(exchangeContract.createStorageOrder(1,
            valid_size, 
            1, 
            valid_price, 
            valid_effective_period, 
            valid_minimumPurchaseSize, 
            valid_guaranteeRatio, 
            new Uint8Array(32)), "shoule be reverted").to.be.revertedWith("Only operator can create order");
    });

    it("sell bill less than min effect pariod", async () => {
        // 最小为56*24
        await expect(exchangeContract.connect(signers[4]).createStorageOrder(1,
            valid_size, 
            1, 
            valid_price, 
            56*23, 
            valid_minimumPurchaseSize, 
            valid_guaranteeRatio, 
            new Uint8Array(32))).to.be.revertedWith("Effective time too short")
    });

    it("sell bill less than min pst price", async () => {
        // 最小为16, 这里是个倍数表示，取值从16~1024, 表示0.125倍到8倍
        await expect(exchangeContract.createStorageOrder(1,
            valid_size, 
            1, 
            8, 
            valid_effective_period, 
            valid_minimumPurchaseSize, 
            valid_guaranteeRatio, 
            new Uint8Array(32))).to.be.revertedWith("Price too low")  
    });

    it("sell bill less than min deposit ratio", async () => {
        // 最小为8
        await expect(exchangeContract.createStorageOrder(1,
            valid_size, 
            1, 
            valid_price, 
            valid_effective_period, 
            valid_minimumPurchaseSize, 
            4, 
            new Uint8Array(32))).to.be.revertedWith("Deposit amount too small");
    });

    it("sell bill", async () => {
        let order_size = 1024*1024*1024*32;
        // 用signer[4]作为operator发一个卖单
        let signers = await hre.ethers.getSigners();
        // 卖方的余额是从signers[3]的账户扣除的
        let before_balance = await pstContract.balanceOf(signers[3].address);
        let receipt = await (await exchangeContract.connect(signers[4]).createStorageOrder(1, order_size, 1, 16, 56*25, 1024*1024*1024*2, 8, new Uint8Array(32))).wait();
        let order_id = (receipt!.logs[0]! as EventLog).args[0];
        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have StorageOrderCreated event").is.equal("StorageOrderCreated");
        expect(order_id, "order id is shoule be 0").is.equal(0);
        
        let order = await exchangeContract.order(order_id);
        expect(order.supplierId, "supplierId mismatch").is.equal(1);
        expect(order.size, "size mismatch").is.equal(order_size);
        expect(order.quality, "quality mismatch").is.equal(1);
        expect(order.price, "price mismatch").is.equal(16);
        expect(order.effectivePeriod, "effectivePeriod mismatch").is.equal(56*25);
        // 检查扣款(PST)是否正确？
        let expect_total_price = _calcTotalPrice(56*25, 16, order_size);
        let depositAmount = _calcDeposit(expect_total_price, 8);
        let after_balance = await pstContract.balanceOf(signers[3].address);
        let actual_deposit = hre.ethers.formatEther(before_balance - after_balance);
        expect(actual_deposit, "total price mismatch").is.equal(depositAmount);
    });

    it("order bill not pass min period", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        await expect(exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).to.be.revertedWith("wait order active")
    });

    let sysBlockPerPeriod = 4*60*3
    it("chain pass min period", async () => {
        await mine(sysBlockPerPeriod*2)
    })

    
    // TODO：等待订单的最小周期过去。可以使用hardhat节点的快进块命令。
    // 在X1上测试时，要怎么做？

    it("order bill when size overflow", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*33;
        await expect(exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).to.be.revertedWith("Not enough storage available")
    });

    it("order bill when Not enough effective time", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        await expect(exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56*100)).to.be.revertedWith("Not enough effective time")
    });

    it("order bill when size too small", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*1;
        await expect(exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).to.be.revertedWith("size too small")
    });

    it("order sell bill", async () => {
        // signers[5]为订单买家
        let signers = await hre.ethers.getSigners();

        // 买方的余额是从自己的账户扣除的
        let before_balance = await pstContract.balanceOf(signers[5].address);
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        let receipt = await (await exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).wait()

        let order_id = (receipt!.logs[0]! as EventLog).args[0];
        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have StoragePurchased event").is.equal("StoragePurchased");
        expect(order_id, "order id is shoule be 1").is.equal(1);
        expect((receipt!.logs[0]! as EventLog).args[1], "order buyer mismatch").is.equal(signers[5].address);
        expect((receipt!.logs[0]! as EventLog).args[2], "order size mismatch").is.equal(size);
        
        let order = await exchangeContract.order(order_id);
        expect(order.supplierId, "supplierId mismatch").is.equal(0);
        expect(order.size, "size mismatch").is.equal(size);
        expect(order.quality, "quality mismatch").is.equal(1);
        expect(order.price, "price mismatch").is.equal(16);
        expect(order.effectivePeriod, "effectivePeriod mismatch").is.equal(56*25);

        // 检查usage是否正确
        let usage = await exchangeContract.usage(rootHash);
        expect(usage.buyer).is.equal(signers[5].address);
        expect(usage.size).is.equal(size);
        expect(usage.orderId).is.equal(order_id);
        // 检查扣款(PST)是否正确？
        let expect_total_price = _calcTotalPrice(56, parseInt(order.price.toString()), size);
        let depositAmount = _calcDeposit(expect_total_price, 8);
        let after_balance = await pstContract.balanceOf(signers[3].address);
        let actual_deposit = hre.ethers.formatEther(before_balance - after_balance);
        expect(actual_deposit, "total price mismatch").is.equal(depositAmount);
    });

    it("order bill when use same hash", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*1;
        await expect(exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).to.be.revertedWith("Already used")
    });

    it("buy bill", async () => {
        // 使用signers[5]挂一个买单
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        // supplierId为0时，表示挂一个买单
        let receipt = await (await exchangeContract.connect(signers[5]).createStorageOrder(0, size, 1, 16, 56*25, size, 8, rootHash)).wait()
        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have StorageOrderCreated event").is.equal("StorageOrderCreated");
        expect((receipt!.logs[0]! as EventLog).args[0], "order id is shoule be 1").is.equal(1);
        // todo: 检查order的属性是否正确
        // todo: 如何检查扣款(PST)是否正确？
    });

    it("order buy bill", async () => {
        // signers[4]为购买之前发的买单
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        let receipt = await (await exchangeContract.connect(signers[4]).buyStorage(1, size, rootHash, 56)).wait()

        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have StoragePurchased event").is.equal("StoragePurchased");
        expect((receipt!.logs[0]! as EventLog).args[0], "order id is shoule be 1").is.equal(1);
        expect((receipt!.logs[0]! as EventLog).args[1], "order buyer mismatch").is.equal(signers[4].address);
        expect((receipt!.logs[0]! as EventLog).args[2], "order size mismatch").is.equal(size);
        // TODO: 检查订单其他属性是否正确
        // TODO: 如何检查扣款是否正确？
    });
})