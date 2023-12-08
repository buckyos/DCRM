import hre from "hardhat";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

describe("PSTToken", () => {
    const totalSupply = 1000;
    async function deployContracts() {
        const signers = await hre.ethers.getSigners();
        const pstContract = await (await hre.ethers.deployContract("PSTToken", [totalSupply])).waitForDeployment();
        return { pstContract, firstHolder: signers[0].address, secondHolder: signers[1].address };
    }

    before(async () => {
        await loadFixture(deployContracts);
    })

    it("should deploy with the initial supply", async () => {
        let { pstContract } = await loadFixture(deployContracts);
        const supply = await pstContract.totalSupply();
        expect(supply).to.equal(totalSupply);
    });

    it("initial holder should have the initial supply", async () => {
        let { pstContract, firstHolder } = await loadFixture(deployContracts);
        const balance = await pstContract.balanceOf(firstHolder);
        expect(balance).to.equal(totalSupply, "Initial holder does not have the initial supply");
    });

    it("should transfer tokens correctly", async () => {
        let amount = 100;
        let { pstContract, firstHolder, secondHolder } = await loadFixture(deployContracts);
        await (await pstContract.transfer(secondHolder, amount, { from: firstHolder })).wait();

        let initialHolderBalance = await pstContract.balanceOf(firstHolder);
        expect(initialHolderBalance).to.equal(totalSupply-100, "Amount wasn't correctly taken from the sender");

        let recipientBalance = await pstContract.balanceOf(secondHolder);
        expect(recipientBalance).to.equal(amount, "Amount wasn't correctly sent to the receiver");
    });

    it("should not allow transferring more than balance", async () => {
        try {
            let { pstContract, firstHolder, secondHolder } = await loadFixture(deployContracts);
            await (await pstContract.transfer(secondHolder, totalSupply * 2, { from: firstHolder })).wait();
            expect(false, "The transfer did not fail as expected");
        } catch (error: any) {
            expect(error, "Expected an error but did not get one");
            expect(error.message.includes("transfer amount exceeds balance"), "Expected 'transfer amount exceeds balance' error message");
        }
    });
});