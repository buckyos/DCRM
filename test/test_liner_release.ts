import { ethers, upgrades } from "hardhat"
import { DMC, LinerRelease } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

describe("LinerRelease", function () {
    let signers: HardhatEthersSigner[];
    let dmc: DMC;
    let liner: LinerRelease
    before(async () => {
        signers = await ethers.getSigners();
        dmc = await (await ethers.deployContract("DMC", [ethers.parseEther("1000000"), [signers[0].address], [ethers.parseEther("1000000")]])).waitForDeployment();
        liner = await (await upgrades.deployProxy(await ethers.getContractFactory("LinerRelease"))).waitForDeployment() as unknown as LinerRelease;
    })

    it("test failed lockup", async () => {
        await expect(liner.startLock(await dmc.getAddress(), ethers.parseEther("100"), signers[1].address, 1000, ethers.parseEther("50"), 500)).to.be.revertedWith("invalid duration")
    })

    it("test success lockup", async () => {
        await (await dmc.approve(await liner.getAddress(), ethers.parseEther("100"))).wait();
        await expect(liner.startLock(await dmc.getAddress(), ethers.parseEther("100"), signers[1].address, 1000, ethers.parseEther("50"), 2000))
            .to.be.emit(liner, "StartLockUp").withArgs(1, signers[1].address)
    })

    it("failed release before first release time", async() => {
        await expect(liner.withdraw(1)).to.be.revertedWith("invalid receiver")
        await expect(liner.connect(signers[1]).withdraw(1)).to.be.revertedWith("not time")
    })

    it("success release all after final release time", async () => {
        await mine(2, {interval: 2000});

        expect(await liner.connect(signers[1]).canWithdraw(1)).to.be.equal(ethers.parseEther("100"))
        let tx = liner.connect(signers[1]).withdraw(1);
        await expect(tx).to.be.emit(liner, "Withdraw").withArgs(1, signers[1].address, ethers.parseEther("100"))
        await expect(tx).to.changeTokenBalance(dmc, signers[1], ethers.parseEther("100"))
    })

    it("success release part after first release time", async () => {
        await (await dmc.approve(await liner.getAddress(), ethers.parseEther("100"))).wait();
        await expect(liner.startLock(await dmc.getAddress(), ethers.parseEther("100"), signers[1].address, 1000, ethers.parseEther("50"), 2000))
            .to.be.emit(liner, "StartLockUp").withArgs(2, signers[1].address)

        await mine(2, {interval: 999});

        // 这里由于block timestamp的精度问题，可能是50，或50.05，或50.1，直接肉眼看了
        console.log(`can withdraw: ${ethers.formatEther(await liner.connect(signers[1]).canWithdraw(2))}`)
        let tx = liner.connect(signers[1]).withdraw(2);
        await expect(tx).to.be.emit(liner, "Withdraw").withArgs(2, signers[1].address, ethers.parseEther("50.05"))
        await expect(tx).to.changeTokenBalance(dmc, signers[1], ethers.parseEther("50.05"))
    })
})