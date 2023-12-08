import hre from "hardhat";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { StorageExchange, PSTToken } from "../typechain-types";
import { EventLog } from "ethers";

describe("StorageExchange", () => {
    let exchangeContract: StorageExchange;
    
    async function deployContracts() {
        const pstContract: PSTToken = await (await hre.ethers.deployContract("PSTToken",[hre.ethers.parseEther("100000")])).waitForDeployment();

        let pstAddress = await pstContract.getAddress();
        const _exchangeContract = await (await hre.ethers.deployContract("StorageExchange", [pstAddress])).waitForDeployment();
        exchangeContract = _exchangeContract as StorageExchange;
        // 给cfo signers[3].address分一些PST
        let signers = await hre.ethers.getSigners();
        await (await pstContract.transfer(signers[3].address, hre.ethers.parseEther("1000"))).wait()
        // 给买家 signers[5].address分一些PST
        await (await pstContract.transfer(signers[5].address, hre.ethers.parseEther("1000"))).wait()
        //return { pstContract, exchangeContract: exchangeContract as StorageExchange };
    }

    before(async () => {
        await deployContracts();
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
        //let { pstContract, exchangeContract } = await loadFixture(deployContracts);
        let signers = await hre.ethers.getSigners();
        //let cfo = signers[1].address;
        //let operator = signers[2].address;
        
        //let receipt = await (await exchangeContract.createSupplier(cfo, [operator], ["https://test.storage.suppily.com"], 100, 200)).wait();

        //let suppilyId = (receipt!.logs[0]! as EventLog).args[0];
        let receipt2 = await (await exchangeContract.updateSupplier(1, signers[3].address, [signers[4].address], ["https://test.storage.suppily2.com"])).wait();

        expect((receipt2!.logs[0]! as EventLog).eventName, "shoule have SupplierChanged event").is.equal("SupplierChanged");
        expect((receipt2!.logs[0]! as EventLog).args[0], "supplier id is shoule be 1").is.equal(1);

        let supplier = await exchangeContract.supplier(1);

        expect(supplier.cfo, "cfo is not correct").is.equal(signers[3].address);
        expect(supplier.operators[0], "operator is not correct").is.equal(signers[4].address);
        expect(supplier.urlprefixs[0], "urlprefixs is not correct").is.equal("https://test.storage.suppily2.com");
    });

    it("sell bill less than min effect pariod", async () => {
        // 最小为56*25
        try {
            await (await exchangeContract.createStorageOrder(1, 10, 1, 16, 56*24, 1, 8, new Uint8Array(32))).wait();
            expect(false, "not fail when effect period less then system min effect period");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("Effective time too short", "error message mismatch")
        }
        
    });

    it("sell bill less than min pst price", async () => {
        // 最小为16, 这里是个倍数表示，取值从16~1024, 表示0.125倍到8倍
        try {
            await (await exchangeContract.createStorageOrder(1, 10, 1, 15, 56*25, 1, 8, new Uint8Array(32))).wait();
            expect(false, "not fail when pst price less then system min pst price");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("Price too low", "error message mismatch")
        }
        
    });

    it("sell bill less than min deposit ratio", async () => {
        // 最小为8
        try {
            await (await exchangeContract.createStorageOrder(1, 10, 1, 16, 56*25, 1, 6, new Uint8Array(32))).wait();
            expect(false, "not fail when deposit ratio less then system min deposit ratio");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("Deposit amount too small", "error message mismatch")
        }
        
    });

    it("sell bill not operator", async () => {
        let signers = await hre.ethers.getSigners();
        try {
            await (await exchangeContract.createStorageOrder(1, 10, 1, 16, 56*25, 1, 8, new Uint8Array(32))).wait();
            expect(false, "not fail when sender not operator");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("Deposit amount too small", "error message mismatch")
        }
    });

    it("sell bill", async () => {
        // 用signer[4]作为operator发一个卖单
        let signers = await hre.ethers.getSigners();
        let receipt = await (await exchangeContract.connect(signers[4]).createStorageOrder(1, 1024*1024*1024*32, 1, 16, 56*25, 1024*1024*1024*2, 8, new Uint8Array(32))).wait();
        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have StorageOrderCreated event").is.equal("StorageOrderCreated");
        expect((receipt!.logs[0]! as EventLog).args[0], "order id is shoule be 0").is.equal(0);
        // todo: 检查order的属性是否正确
        // todo: 如何检查扣款(PST)是否正确？
    });

    it("order bill not pass min period", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        try {
            await (await exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).wait()
            expect(false, "not fail when order not pass min period");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("wait order active", "error message mismatch")
        }
    });

    let sysBlockPerPeriod = 4*60*3
    // TODO：等待订单的最小周期过去。可以使用hardhat节点的快进块命令。
    // 在X1上测试时，要怎么做？

    it("order bill when size overflow", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*33;
        try {
            await (await exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).wait()
            expect(false, "not fail when order size overflow");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("Not enough storage available", "error message mismatch")
        }
    });

    it("order bill when Not enough effective time", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        try {
            await (await exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56*100)).wait()
            expect(false, "not fail when order size overflow");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("Not enough effective time", "error message mismatch")
        }
    });

    it("order bill when size too small", async () => {
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*1;
        try {
            await (await exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).wait()
            expect(false, "not fail when order size overflow");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message).include("size too small", "error message mismatch")
        }
    });

    it("order sell bill", async () => {
        // signers[5]为订单买家
        let signers = await hre.ethers.getSigners();
        let rootHash = hre.ethers.randomBytes(32);
        let size = 1024*1024*1024*2.5;
        let receipt = await (await exchangeContract.connect(signers[5]).buyStorage(0, size, rootHash, 56)).wait()

        expect((receipt!.logs[0]! as EventLog).eventName, "shoule have StoragePurchased event").is.equal("StoragePurchased");
        expect((receipt!.logs[0]! as EventLog).args[0], "order id is shoule be 0").is.equal(0);
        expect((receipt!.logs[0]! as EventLog).args[1], "order buyer mismatch").is.equal(signers[5].address);
        expect((receipt!.logs[0]! as EventLog).args[2], "order size mismatch").is.equal(size);
        // TODO: 检查订单其他属性是否正确
        // TODO: 如何检查扣款是否正确？
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