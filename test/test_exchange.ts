import { ethers, upgrades } from "hardhat"
import { DMCToken, Exchange, GWTToken } from "../typechain-types"
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from "chai";

describe("Exchange", function () {
    let dmc: DMCToken
    let gwt: GWTToken
    let exchange: Exchange
    let signers: HardhatEthersSigner[];

    before(async () => {
        signers = await ethers.getSigners()

        dmc = await (await ethers.deployContract("DMCToken", [ethers.parseEther("1000000000"), [], []])).waitForDeployment()
        gwt = await (await ethers.deployContract("GWTToken")).waitForDeployment()
        exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"), 
            [await dmc.getAddress(), await gwt.getAddress()], 
            {
                initializer: "initialize",
                kind: "uups",
                timeout: 0
            })).waitForDeployment() as unknown as Exchange;

        await (await gwt.enableMinter([await exchange.getAddress()])).wait();
        await (await dmc.enableMinter([await exchange.getAddress()])).wait();
    })

    it("mint dmc", async () => {
        await (await exchange.allowMintDMC(signers[0].address, "cookie1", ethers.parseEther("500"))).wait();

        await expect(exchange.connect(signers[1]).allowMintDMC(signers[1].address, "cookie2", ethers.parseEther("1500"))).revertedWith("not mint admin");
        await expect(exchange.connect(signers[1]).mintDMC("cookie1")).revertedWith("cannot mint");

        await expect(exchange.mintDMC("cookie1")).changeTokenBalance(dmc, signers[0].address, ethers.parseEther("500"));

        await expect(exchange.mintDMC("cookie1")).revertedWith("cannot mint");

        await (await exchange.setMintAdmin(signers[1].address)).wait();
        await (await exchange.connect(signers[1]).allowMintDMC(signers[1].address, "cookie2", ethers.parseEther("1000"))).wait();
        await expect(exchange.connect(signers[1]).mintDMC("cookie2")).changeTokenBalance(dmc, signers[1].address, ethers.parseEther("1000"));
    });

    it("exchange dmc to gwt", async () => {
        expect(await dmc.balanceOf(signers[1].address)).to.equal(ethers.parseEther("1000"))
        let exchangeAddr = await exchange.getAddress();

        await expect(dmc.connect(signers[1]).approve(exchangeAddr, ethers.parseEther("1")))
            .emit(dmc, "Approval").withArgs(signers[1].address, exchangeAddr, ethers.parseEther("1"))

        await expect(exchange.connect(signers[1]).exchangeGWT(ethers.parseEther("1")))
            .emit(gwt, "Transfer").withArgs(ethers.ZeroAddress, signers[1].address, ethers.parseEther("210"))
        
        expect(await gwt.balanceOf(signers[1].address)).to.equal(ethers.parseEther("210"))
        expect(await dmc.balanceOf(signers[1].address)).to.equal(ethers.parseEther("999"))
        expect(await dmc.balanceOf(exchangeAddr)).to.equal(ethers.parseEther("1"))
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
        let exchangeAddr = await exchange.getAddress();

        await expect(gwt.connect(signers[1]).approve(exchangeAddr, ethers.parseEther("210")))
            .emit(gwt, "Approval").withArgs(signers[1].address, exchangeAddr, ethers.parseEther("210"))

        await expect(exchange.connect(signers[1]).exchangeDMC(ethers.parseEther("210")))
            .emit(gwt, "Transfer").withArgs(signers[1].address, ethers.ZeroAddress, ethers.parseEther("210"))

        expect(await gwt.balanceOf(signers[1].address)).to.equal(0)
        expect(await dmc.balanceOf(signers[1].address)).to.equal(ethers.parseEther("1000"))
    });

    it("mint disallowed", async () => {
        await expect(gwt.connect(signers[1]).mint(signers[1].address, ethers.parseEther("1"))).revertedWith("mint not allowed");
    });
})