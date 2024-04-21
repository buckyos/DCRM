import { ethers, upgrades } from "hardhat"
import { DMC2, GWTToken2, DividendContract } from "../typechain-types"
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

describe("Devidend", function () {
    let dmc: DMC2
    let gwt: GWTToken2
    let dividend: DividendContract;
    let signers: HardhatEthersSigner[];

    before(async () => {
        signers = await ethers.getSigners()

        dmc = await (await ethers.deployContract("DMC2", [ethers.parseEther("1000000000"), [signers[0].address], [1000000]])).waitForDeployment()
        gwt = await (await ethers.deployContract("GWTToken2")).waitForDeployment()
        dividend = await (await ethers.deployContract("DividendContract", [await dmc.getAddress(), 100])).waitForDeployment()

        // 给signers[0] 1000个GWT
        await (await gwt.enableMinter([signers[0].address])).wait()
        await (await gwt.mint(signers[0].address, 1000)).wait()
        await (await gwt.approve(await dividend.getAddress(), 1000)).wait()

        // 给signers[1]到19, 每人100个DMC
        for (let i = 1; i < 20; i++) {
            await (await dmc.transfer(signers[i].address, 100)).wait()
            await (await dmc.connect(signers[i]).approve(await dividend.getAddress(), 100)).wait()
        }

    })

    it("test", async () => {
        // 第0周期，打入收入100 GWT
        await (await dividend.deposit(100, await gwt.getAddress())).wait();

        // 第0周期，signers1，2抵押50 DMC
        await (await dividend.connect(signers[1]).stake(50)).wait()
        await (await dividend.connect(signers[2]).stake(50)).wait()

        // 前进到第一周期
        mine(100);

        // 第一周期，第0周期的人是提不到分红的，100 GWT归入此周期
        //await (await dividend.settleDevidend(0)).wait()

        // 尝试提取分红，应该是提不到的
        await (await dividend.connect(signers[1]).withdrawDividend());
        expect(await gwt.balanceOf(signers[1].address)).to.equal(0);
        
        // 直接前进到第二周期
        mine(100);
        await (await dividend.settleDevidend(1)).wait()

        // 此时提现第一周期的，应该能提到50 GWT
        await (await dividend.connect(signers[1]).withdrawDividend());
        expect(await gwt.balanceOf(signers[1].address)).to.equal(50);

        // 第二周期，又打入100 GWT
        await (await dividend.deposit(100, await gwt.getAddress())).wait();

        // 第二周期，signer1提取25 DMC出来
        await (await dividend.connect(signers[1]).withdraw(25)).wait();

        // 前进到第三周期
        mine(100);
        await (await dividend.settleDevidend(2)).wait()

        // 此时提现第二周期的，应该能提到33 GWT
        await (await dividend.connect(signers[1]).withdrawDividend());
        expect(await gwt.balanceOf(signers[1].address)).to.equal(83);

        // signers2提取两个周期的分红，应该能提到50+66=116 GWT
        await (await dividend.connect(signers[2]).withdrawDividend());
        expect(await gwt.balanceOf(signers[2].address)).to.equal(116);
    })
})