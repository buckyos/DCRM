import { ethers, upgrades } from "hardhat"
import { DMC, Exchange, GWT } from "../typechain-types"
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

// 此测试运行的前提：每轮的释放DMC固定为210，汇率固定为210

describe("Exchange", function () {
    let dmc: DMC
    let gwt: GWT
    let exchange: Exchange
    let signers: HardhatEthersSigner[];

    before(async () => {
        signers = await ethers.getSigners()

        console.log("signers 0:", signers[0].address)

        dmc = await (await ethers.deployContract("DMC", [ethers.parseEther("1000000000"), [signers[0].address], [ethers.parseEther("100000")]])).waitForDeployment()
        gwt = await (await ethers.deployContract("GWT", [[], []])).waitForDeployment()
        //exchange = await(await ethers.deployContract("Exchange2", [await dmc.getAddress(), await gwt.getAddress(), ethers.ZeroAddress, 1000])).waitForDeployment();
        exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"), 
            [await dmc.getAddress(), await gwt.getAddress(), ethers.ZeroAddress, 1000], 
            {
                initializer: "initialize",
                kind: "uups",
                timeout: 0
            })).waitForDeployment() as unknown as Exchange;
        console.log("exchange:", await exchange.getAddress());
        
        await (await gwt.enableMinter([await exchange.getAddress(), signers[0].address])).wait();
        await (await dmc.enableMinter([await exchange.getAddress()])).wait();

        // 给一些测试用的gwt先
        await (await gwt.mint(signers[0].address, ethers.parseEther("10000000"))).wait();
    })

    it("test cycle", async () => {
        expect(await dmc.totalSupply()).to.equal(ethers.parseEther("1000000000"));
        expect(await dmc.balanceOf(await dmc.getAddress())).to.equal(ethers.parseEther("999900000"));

        // 测试模式
        await expect(exchange.freeMintGWT()).to.revertedWith("no free mint balance");

        await (await gwt.approve(await exchange.getAddress(), ethers.parseEther("210"))).wait();
        await (await exchange.addFreeMintBalance(ethers.parseEther("210"))).wait();

        await expect(exchange.freeMintGWT()).to.changeTokenBalance(gwt, signers[0], ethers.parseEther("210"));
        await expect(exchange.freeMintGWT()).to.revertedWith("already free minted");

        await (await dmc.approve(await exchange.getAddress(), ethers.parseEther("1"))).wait();
        await (await exchange.addFreeDMCTestMintBalance(ethers.parseEther("1"))).wait();

        expect(exchange.GWTToDMCForTest(ethers.parseEther("210"))).to.changeTokenBalance(dmc, signers[0], ethers.parseEther("1"));

        await expect(exchange.GWTtoDMC(ethers.parseEther("210"))).to.be.revertedWith("contract in test mode");
    })

    it("enable prod mode", async () => {
        await (await exchange.enableProdMode()).wait();

        await expect(exchange.enableProdMode()).to.revertedWith("contract not in test mode");
        await expect(exchange.GWTToDMCForTest(ethers.parseEther("100"))).to.revertedWith("contract not in test mode");
    });

    it("cycle 1", async () => {
        // 兑换DMC到GWT
        await (await dmc.approve(await exchange.getAddress(), ethers.parseEther("1"))).wait();

        // 用1 DMC兑换GWT，能兑换1*210*1.2个
        await expect(exchange.DMCtoGWT(ethers.parseEther("1"))).to.changeTokenBalance(gwt, signers[0], ethers.parseEther((1*210*1.2).toString()));
    });

    it("cycle 2", async () => {
        // 前进到时间1000之后，开启下一轮
        mine(2, {interval: 1000});

        // 由于上一轮没有人兑换DMC，本轮的可兑换余额为210 + 210/1=420, rate变为210
        // 我们兑换320个DMC出来，需要320*210=67200个GWT
        await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("67200"))).wait();
        const tx = await exchange.GWTtoDMC(ethers.parseEther("67200"));
        await expect(tx).to.changeTokenBalance(gwt, signers[0], ethers.parseEther("-67200"));
        await expect(tx).to.changeTokenBalance(dmc, signers[0], ethers.parseEther("320"));
        await expect(tx).to.changeTokenBalance(gwt, await exchange.getAddress(), ethers.parseEther("67200"));

        expect((await exchange.getCycleInfo())).to.deep.equal([2n, ethers.parseEther("100"), ethers.parseEther("420")])
    })

    it("cycle 3", async () => {
        // 前进到时间1000之后，开启下一轮
        mine(2, {interval: 1000});

        // 上一轮剩余100，此轮的可兑换额度为210 + 100/2 = 260, 储存的可兑换额度为100/2=50
        // 再兑换160个DMC，需要160*210=33600个GWT
        await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("33600"))).wait();
        const tx = await exchange.GWTtoDMC(ethers.parseEther("33600"));

        await expect(tx).to.changeTokenBalance(gwt, signers[0], ethers.parseEther("-33600"));
        await expect(tx).to.changeTokenBalance(dmc, signers[0], ethers.parseEther("160"));
        await expect(tx).to.changeTokenBalance(gwt, await exchange.getAddress(), ethers.parseEther("33600"));

        expect((await exchange.getCycleInfo())).to.deep.equal([3n, ethers.parseEther("100"), ethers.parseEther("260")])
    })

    it("cycle 4", async () => {
        // 前进到时间1000之后，开启下一轮
        mine(2, {interval: 1000});

        // 上一轮又剩余100，此轮的可兑换额度为210+(100+50)/3=260，储存的可兑换额度为100
        // 这次我们把260个都兑换掉, 需要260*210=54600个GWT

        await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("54600"))).wait();
        const tx = await exchange.GWTtoDMC(ethers.parseEther("54600"));

        await expect(tx).to.changeTokenBalance(gwt, signers[0], ethers.parseEther("-54600"));
        await expect(tx).to.changeTokenBalance(dmc, signers[0], ethers.parseEther("260"));
        await expect(tx).to.changeTokenBalance(gwt, await exchange.getAddress(), ethers.parseEther("54600"));

        expect((await exchange.getCycleInfo())).to.deep.equal([4n, ethers.parseEther("0"), ethers.parseEther("260")])
    });

    it("cycle 5", async () => {
        // 前进到时间1000之后，开启下一轮
        mine(2, {interval: 1000});
        // 上一轮没有剩余，本轮的可兑换额度为210 + 100 / 2 = 260, 储存的可兑换额度为50
        // 这次我们把260个都兑换掉, 需要260*210=54600个GWT
        await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("54600"))).wait();
        const tx = await exchange.GWTtoDMC(ethers.parseEther("54600"));

        await expect(tx).to.changeTokenBalance(gwt, signers[0], ethers.parseEther("-54600"));
        await expect(tx).to.changeTokenBalance(dmc, signers[0], ethers.parseEther("260"));
        await expect(tx).to.changeTokenBalance(gwt, await exchange.getAddress(), ethers.parseEther("54600"));

        expect((await exchange.getCycleInfo())).to.deep.equal([5n, ethers.parseEther("0"), ethers.parseEther("260")])
    });
})