import { ethers, upgrades } from "hardhat";
import { DividendContract, Exchange } from "../typechain-types";
import {mine} from "@nomicfoundation/hardhat-network-helpers";

async function main() {
    let signers = await ethers.getSigners()

    console.log("signers 0:", signers[0].address)

    let dmc = await (await ethers.deployContract("DMC", [ethers.parseEther("1000000000"), [signers[0].address], [ethers.parseEther("100000")]])).waitForDeployment()
    let gwt = await (await ethers.deployContract("GWT", [[signers[0].address], [ethers.parseEther("10000000")]])).waitForDeployment()
    //exchange = await(await ethers.deployContract("Exchange2", [await dmc.getAddress(), await gwt.getAddress(), ethers.ZeroAddress, 1000])).waitForDeployment();
    let exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"), 
        [await dmc.getAddress(), await gwt.getAddress(), ethers.ZeroAddress, 1000], 
        {
            initializer: "initialize",
            kind: "uups",
            timeout: 0
        })).waitForDeployment() as unknown as Exchange;
    console.log("exchange:", await exchange.getAddress());
    
    await (await gwt.enableMinter([await exchange.getAddress()])).wait();
    await (await dmc.enableMinter([await exchange.getAddress()])).wait();

    // 测试模式
    await (await gwt.approve(await exchange.getAddress(), ethers.parseEther("210"))).wait();
    await (await exchange.addFreeMintBalance(ethers.parseEther("210"))).wait();

    await(await exchange.freeMintGWT()).wait()

    await (await dmc.approve(await exchange.getAddress(), ethers.parseEther("1"))).wait();
    await (await exchange.addFreeDMCTestMintBalance(ethers.parseEther("1"))).wait();

    await (await gwt.approve(await exchange.getAddress(), ethers.parseEther("210"))).wait();
    await (await exchange.GWTToDMCForTest(ethers.parseEther("210"))).wait();

    mine(20, {interval: 1000});
    await (await exchange.enableProdMode()).wait();

    await (await dmc.approve(await exchange.getAddress(), ethers.parseEther("1"))).wait();

        // 用1 DMC兑换GWT，能兑换1*210*1.2个
    await (await exchange.DMCtoGWT(ethers.parseEther("1"))).wait();

    // 前进到时间1000之后，开启下一轮
    mine(2, {interval: 1000});

    // 由于上一轮没有人兑换DMC，本轮的可兑换余额为210 + 210/1=420, rate变为210
    // 我们兑换320个DMC出来，需要320*210=67200个GWT
    await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("67200"))).wait();
    let tx = await exchange.GWTtoDMC(ethers.parseEther("67200"));
    await tx.wait();


    // 前进到时间1000之后，开启下一轮
    mine(2, {interval: 1000});

    // 上一轮剩余100，此轮的可兑换额度为210 + 100/2 = 260, 储存的可兑换额度为100/2=50
    // 再兑换160个DMC，需要160*210=33600个GWT
    await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("33600"))).wait();
    tx = await exchange.GWTtoDMC(ethers.parseEther("33600"));
    await tx.wait();

    // 前进到时间1000之后，开启下一轮
    mine(2, {interval: 1000});

    // 上一轮又剩余100，此轮的可兑换额度为210+(100+50)/3=260，储存的可兑换额度为100
    // 这次我们把260个都兑换掉, 需要260*210=54600个GWT

    await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("54600"))).wait();
    tx = await exchange.GWTtoDMC(ethers.parseEther("54600"));

    await tx.wait();

    // 前进到时间1000之后，开启下一轮
    mine(2, {interval: 1000});
    // 上一轮没有剩余，本轮的可兑换额度为210 + 100 / 2 = 260, 储存的可兑换额度为50
    // 这次我们把260个都兑换掉, 需要260*210=54600个GWT
    await(await gwt.approve(await exchange.getAddress(), ethers.parseEther("54600"))).wait();
    tx = await exchange.GWTtoDMC(ethers.parseEther("54600"));
}

main().then(() => process.exit(0));