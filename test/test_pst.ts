import hre from "hardhat";
import { expect } from "chai";
import { GWTToken } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("GWTToken", function () {
    const totalSupply = 1000;
    let signers: HardhatEthersSigner[];
    let pstContract: GWTToken;
    async function deployContracts() {
        pstContract = await (await hre.ethers.deployContract("GWTToken", [totalSupply])).waitForDeployment();
    }

    before(async () => {
        await deployContracts();
        signers = await hre.ethers.getSigners()
    })

    it("should deploy with the initial supply", async () => {
        const supply = await pstContract.totalSupply();
        expect(supply).to.equal(totalSupply);
    });

    it("initial holder should have the initial supply", async () => {
        const balance = await pstContract.balanceOf(signers[0].address);
        expect(balance).to.equal(totalSupply, "Initial holder does not have the initial supply");
    });

    it("should transfer tokens correctly", async () => {
        let amount = 100;
        await (await pstContract.transfer(signers[1].address, amount, { from: signers[0].address })).wait();

        let initialHolderBalance = await pstContract.balanceOf(signers[0].address);
        expect(initialHolderBalance).to.equal(totalSupply-100, "Amount wasn't correctly taken from the sender");

        let recipientBalance = await pstContract.balanceOf(signers[1].address);
        expect(recipientBalance).to.equal(amount, "Amount wasn't correctly sent to the receiver");
    });

    it("should not allow transferring more than balance", async () => {
        await expect(pstContract.transfer(signers[1].address, totalSupply * 2, { from: signers[0].address }))
            .to.be.revertedWithCustomError(pstContract, "ERC20InsufficientBalance");
    });
});