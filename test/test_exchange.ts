import { ethers } from "hardhat"
import { DMCToken, GWTToken } from "../typechain-types"
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from "chai";

describe("Exchange", function () {
    let dmc: DMCToken
    let gwt: GWTToken
    let signers: HardhatEthersSigner[];

    before(async () => {
        signers = await ethers.getSigners()

        dmc = await (await ethers.deployContract("DMCToken", [ethers.parseEther("10000000")])).waitForDeployment()
        let dmcAddr = await dmc.getAddress();
        gwt = await (await ethers.deployContract("GWTToken", [dmcAddr])).waitForDeployment()

        await (await dmc.transfer(signers[1].address, ethers.parseEther("1000"))).wait()
    })

    it("exchange dmc to gwt", async () => {
        expect(await dmc.balanceOf(signers[1].address)).to.equal(ethers.parseEther("1000"))
        let gwtAddr = await gwt.getAddress();
        await expect(dmc.connect(signers[1]).approve(gwtAddr, ethers.parseEther("1")))
            .emit(dmc, "Approval").withArgs(signers[1].address, gwtAddr, ethers.parseEther("1"))

        await expect(gwt.connect(signers[1]).exchange(ethers.parseEther("1")))
            .emit(gwt, "Transfer").withArgs(ethers.ZeroAddress, signers[1].address, ethers.parseEther("210"))
        
        expect(await gwt.balanceOf(signers[1].address)).to.equal(ethers.parseEther("210"))
        expect(await dmc.balanceOf(signers[1].address)).to.equal(ethers.parseEther("999"))
        expect(await dmc.balanceOf(gwtAddr)).to.equal(ethers.parseEther("1"))
    })

    it("unregistered transfer will be reverted", async () => {
        await expect(gwt.connect(signers[1]).transfer(signers[2].address, ethers.parseEther("1")))
            .to.be.revertedWith("transfer not allowed")
    })

    it("register transfer", async () => {
        // register signers[2]
        await expect(gwt.connect(signers[0]).enableTransfer([signers[2].address])).to.be.ok;

        // transfer to signers[2] success
        await expect(gwt.connect(signers[1]).transfer(signers[2].address, ethers.parseEther("1")))
            .emit(gwt, "Transfer").withArgs(signers[1].address, signers[2].address, ethers.parseEther("1"))

        expect(await gwt.balanceOf(signers[2].address)).to.equal(ethers.parseEther("1"))

        // transfer from signers[2] success
        await expect(gwt.connect(signers[2]).transfer(signers[1].address, ethers.parseEther("1")))
            .emit(gwt, "Transfer").withArgs(signers[2].address, signers[1].address, ethers.parseEther("1"))

        expect(await gwt.balanceOf(signers[2].address)).to.equal(0)
    })

    it("burn", async () => {
        await expect(gwt.connect(signers[1]).burn(ethers.parseEther("210")))
            .emit(gwt, "Transfer").withArgs(signers[1].address, ethers.ZeroAddress, ethers.parseEther("210"))

        expect(await gwt.balanceOf(signers[1].address)).to.equal(0)
        expect(await dmc.balanceOf(signers[1].address)).to.equal(ethers.parseEther("1000"))
    });
})