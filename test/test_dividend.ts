import { ethers, upgrades } from "hardhat"
import { DMC2, GWTToken2, Dividend2 } from "../typechain-types"
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

describe("Devidend", function () {
    let dmc: DMC2
    let gwt: GWTToken2
    let dividend: Dividend2;
    let signers: HardhatEthersSigner[];

    before(async () => {
        signers = await ethers.getSigners()

        dmc = await (await ethers.deployContract("DMC2", [ethers.parseEther("1000000000"), [signers[0].address], [1000000]])).waitForDeployment()
        gwt = await (await ethers.deployContract("GWTToken2")).waitForDeployment()
        dividend = await (await ethers.deployContract("Dividend2", [await dmc.getAddress(), 1000])).waitForDeployment()

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
        mine(1000);
        // 打入收入100 GWT, 前进到周期1
        await (await dividend.deposit(100, await gwt.getAddress())).wait();

        // 第1周期，signers1，2抵押50 DMC
        await (await dividend.connect(signers[1]).stake(50)).wait()
        await (await dividend.connect(signers[2]).stake(50)).wait()
        
        // 又打入100 GWT，前进到周期2, 此时总分红200 GWT
        
        mine(1000);
        await (await dividend.deposit(100, await gwt.getAddress())).wait();
        //await (await dividend.settleDevidend(1)).wait()

        // 因为周期1开始时没有已确定的抵押，周期1的分红是提不到的
        expect(dividend.connect(signers[1]).withdraw([1])).to.be.revertedWith("no dividend");

        // 前进到周期3，周期2的分红200 GWT,周期3的分红100 GWT
        mine(1000);
        await (await dividend.deposit(100, await gwt.getAddress())).wait();

        // 此时提现周期2的，应该能提到100 GWT
        await (await dividend.connect(signers[1]).withdraw([2]));
        expect(await gwt.balanceOf(signers[1].address)).to.equal(100);
        
        // 周期3，signer1提取25 DMC出来
        await (await dividend.connect(signers[1]).unStake(25)).wait();

        // 强制结算周期3，进入周期4
        mine(1000);
        await (await dividend.deposit(0, ethers.ZeroAddress)).wait();
        //await (await dividend.settleDevidend(2)).wait()

        // 此时提现周期3的，应该能提到33 GWT
        await (await dividend.connect(signers[1]).withdraw([3]));
        expect(await gwt.balanceOf(signers[1].address)).to.equal(133);

        // signers2提取两个周期的分红，应该能提到100+66=166 GWT
        await (await dividend.connect(signers[2]).withdraw([2,3]));
        expect(await gwt.balanceOf(signers[2].address)).to.equal(166);
    })
})