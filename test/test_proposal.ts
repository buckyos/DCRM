import { ethers, upgrades } from "hardhat";
import { DMC, GWT, DividendContract, ProposalContract } from "../typechain-types";
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/signers';
import { expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers"

describe("Proposal", function () {
    let dmc: DMC
    let gwt: GWT
    let dividend: DividendContract;
    let proposal: ProposalContract;
    let signers: HardhatEthersSigner[];
    before(async function () {
        signers = await ethers.getSigners();
        dmc = await (await ethers.deployContract("DMC", [ethers.parseEther("1000000000"), [signers[0].address], [ethers.parseEther("1000000")]])).waitForDeployment()
        gwt = await (await ethers.deployContract("GWT", [[], []])).waitForDeployment()

        dividend = await upgrades.deployProxy(
            await ethers.getContractFactory("DividendContract"),
            [await dmc.getAddress(), 1000, [await gwt.getAddress()], 60 * 60 * 24 * 3, ethers.ZeroAddress]
        ) as unknown as DividendContract;

        proposal = await upgrades.deployProxy(
            await ethers.getContractFactory("ProposalContract"),
            [await dividend.getAddress(), 3*24*60*60, ethers.parseEther("50000")]) as unknown as ProposalContract;

        await (await dividend.updateProposalContract(await proposal.getAddress())).wait();
        await (await dmc.transfer(signers[1].address, ethers.parseEther("100000"))).wait();
        await (await dmc.transfer(signers[2].address, ethers.parseEther("100000"))).wait();
        await (await dmc.transfer(signers[3].address, ethers.parseEther("100000"))).wait();

        for (let i = 0; i < 4; i++) {
            console.log(`signer ${i}: ${signers[i].address}`);
        }
    });

    it("create proposal fail", async () => {
        await expect(proposal.createProposal(
            "testTitle",
            "testContent",
            4 * 24 * 60 * 60)).to.be.revertedWith("Duration too long");

        await expect(proposal.createProposal(
            "testTitle",
            "testContent",
            3 * 24 * 60 * 60)).to.be.revertedWith("Locked amount not enough");
    });

    it("create proposal", async () => {
        await (await dmc.approve(await dividend.getAddress(), ethers.parseEther("60000"))).wait();
        await (await dividend.stake(ethers.parseEther("60000"))).wait();

        // pass 1 day
        await mine(2, {interval: 24*60*60})

        await expect(proposal.createProposal("testTitle", "testContent", 2.25*24*60*60)).to.emit(proposal, "CreateProposal").withArgs(1);

        // pass 2 days
        await mine(2, {interval: 2*24*60*60})

        // cant unstack because lock time extended
        await expect(dividend.unstake(ethers.parseEther("10000"))).to.be.revertedWith("Unstake is locked");

        // pass 1 day again
        await mine(2, {interval: 24*60*60})
        await expect(dividend.unstake(ethers.parseEther("10000"))).to.emit(dividend, "Unstake").withArgs(signers[0].address, ethers.parseEther("10000"));

    });

    it("vote proposal", async () => {
        await (await dmc.connect(signers[1]).approve(await dividend.getAddress(), 700)).wait();
        await (await dividend.connect(signers[1]).stake(700)).wait();

        await (await dmc.connect(signers[2]).approve(await dividend.getAddress(), 5000)).wait();
        await (await dividend.connect(signers[2]).stake(5000)).wait();

        await (await dmc.connect(signers[3]).approve(await dividend.getAddress(), 3000)).wait();
        await (await dividend.connect(signers[3]).stake(3000)).wait();


        await expect(proposal.createProposal("testTitle", "testContent", 1*24*60*60)).to.emit(proposal, "CreateProposal").withArgs(2);

        // pass 2 days
        await mine(2, {interval: 2*24*60*60})

        await expect(proposal.connect(signers[1]).supportProposal(2, "signer 1 support")).to.revertedWith("Proposal ended");

        await expect(proposal.createProposal("testTitle", "testContent", 3*24*60*60)).to.emit(proposal, "CreateProposal").withArgs(3);
        await expect(proposal.connect(signers[1]).supportProposal(3, "signer 1 support")).to.emit(proposal, "Vote")
            .withArgs(3, signers[1].address, true, 700, "signer 1 support");
        await expect(proposal.connect(signers[1]).supportProposal(3, "signer 1 support again")).to.revertedWith("Already voted");

        await expect(proposal.connect(signers[2]).opposeProposal(3, "signer 2 support")).to.emit(proposal, "Vote")
            .withArgs(3, signers[2].address, false, 5000, "signer 2 support");

        await expect(proposal.connect(signers[3]).supportProposal(3, "signer 3 support")).to.emit(proposal, "Vote")
            .withArgs(3, signers[3].address, true, 3000, "signer 3 support");

        let brief = await proposal.getProposal(3);

        expect(brief.totalOppose).to.equal(5000);
        expect(brief.totalSupport).to.equal(3700);
        expect(brief.totalVotes).to.equal(3);

        let votes = await proposal.getProposalVotes(3, 0, 10);
        expect(votes.length).to.equal(3);
        expect(votes[0]).to.deep.equal([signers[1].address, true, 700, "signer 1 support"]);
        expect(votes[1]).to.deep.equal([signers[2].address, false, 5000, "signer 2 support"]);
        expect(votes[2]).to.deep.equal([signers[3].address, true, 3000, "signer 3 support"]);
    })
});