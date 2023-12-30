import { ethers } from "hardhat";
import { expect } from "chai";
import { DMCToken, FakeNFTContract, GWTToken, PublicDataStorage } from "../typechain-types";

import * as TestDatas from "../testDatas/test_data.json";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ContractTransactionResponse } from "ethers";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

import { generateProof } from "../scripts/generate_proof";

/**
 * 0: data owner
 * 1: data sponser
 * 2-10: data supplier
 * 19: Foundation
 * 14: normal flow, large balance
 * 15: failed owner: all paid to create public data
 * 16: other large balance
 * 17: all paid to deposit public data, and append 1 dmc
 */

describe("PublicDataStorage", function () {
    let contract: PublicDataStorage;
    let dmcToken: DMCToken;
    let gwtToken: GWTToken;
    let signers: HardhatEthersSigner[];
    let nftContract: FakeNFTContract

    async function deployContracts() {
        let listLibrary = await (await ethers.getContractFactory("SortedScoreList")).deploy();
        let proofLibrary = await (await ethers.getContractFactory("PublicDataProof")).deploy();

        dmcToken = await (await ethers.deployContract("DMCToken", [ethers.parseEther("10000000")])).waitForDeployment()
        gwtToken = await (await ethers.deployContract("GWTToken", [await dmcToken.getAddress()])).waitForDeployment()

        // nftContract = await (await hre.ethers.deployContract("FakeNFTContract")).waitForDeployment();
        contract = await (await ethers.deployContract("PublicDataStorage", [await gwtToken.getAddress(), signers[19].address], {libraries: {
            SortedScoreList: await listLibrary.getAddress(),
            PublicDataProof: await proofLibrary.getAddress()
        }})).waitForDeployment();

        await (await gwtToken.enableTransfer([await contract.getAddress()])).wait();
    }

    before(async () => {
        signers = await ethers.getSigners()
        await deployContracts();

        for (const signer of signers) {
            await (await dmcToken.transfer(await signer.address, ethers.parseEther("1000"))).wait();
            await (await dmcToken.connect(signer).approve(await gwtToken.getAddress(), ethers.parseEther("1000"))).wait();
            await (await gwtToken.connect(signer).exchange(ethers.parseEther("1000"))).wait();
            await (await gwtToken.connect(signer).approve(await contract.getAddress(), ethers.parseEther("210000"))).wait();
        }

        // large balance
        await (await dmcToken.transfer(await signers[14].address, ethers.parseEther("1000000"))).wait();
        await (await dmcToken.connect(signers[14]).approve(await gwtToken.getAddress(), ethers.parseEther("1000000"))).wait();
        await (await gwtToken.connect(signers[14]).exchange(ethers.parseEther("1000000"))).wait();
        await (await gwtToken.connect(signers[14]).approve(await contract.getAddress(), ethers.parseEther("210000000"))).wait();
        
        await (await dmcToken.transfer(await signers[16].address, ethers.parseEther("1000000"))).wait();
        await (await dmcToken.connect(signers[16]).approve(await gwtToken.getAddress(), ethers.parseEther("1000000"))).wait();
        await (await gwtToken.connect(signers[16]).exchange(ethers.parseEther("1000000"))).wait();
        await (await gwtToken.connect(signers[16]).approve(await contract.getAddress(), ethers.parseEther("210000000"))).wait();
    });

    it("create public data", async () => {
        // 需要的最小抵押：1/8 GB * 96(周) * 64(倍) = 768 GWT
        await expect(contract.createPublicData(TestDatas[0].hash, 64, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .emit(contract, "PublicDataCreated").withArgs(TestDatas[0].hash)
            .emit(contract, "SponsorChanged").withArgs(TestDatas[0].hash, ethers.ZeroAddress, signers[0].address)
            .emit(contract, "DepositData").withArgs(signers[0].address, TestDatas[0].hash, ethers.parseEther("614.4"), ethers.parseEther("153.6"));

        expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("614.4"));
    });

    it("create public data failed", async () => {
        // duplicate create
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[0].hash, 64, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .to.be.revertedWith("public data already exists")

        // invalid hash
        await expect(contract.connect(signers[15]).createPublicData(ethers.ZeroHash, 64, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .to.be.revertedWith("data hash is empty")

        // // too little
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 0, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .to.be.revertedWith("deposit ratio is too small")
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 63, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .to.be.revertedWith("deposit ratio is too small")
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 64, ethers.parseEther("0"), ethers.ZeroAddress, 0))
            .to.be.revertedWith("deposit amount is too small")
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 64, ethers.parseEther("767.9"), ethers.ZeroAddress, 0))
            .to.be.revertedWith("deposit amount is too small")

        // // more then total gwt amounts
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 64, ethers.parseEther("210001"), ethers.ZeroAddress, 0))
            .to.be.reverted;

        // cut the appropriate amount
        await (await gwtToken.connect(signers[15]).approve(await contract.getAddress(), ethers.parseEther("767"))).wait();
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 64, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .to.be.reverted;

        // cost all gwts
        await (await gwtToken.connect(signers[15]).approve(await contract.getAddress(), ethers.parseEther("210000"))).wait();
        await expect(contract.connect(signers[15]).createPublicData(TestDatas[9].hash, 64, ethers.parseEther("210000"), ethers.ZeroAddress, 0))
            .emit(contract, "PublicDataCreated").withArgs(TestDatas[9].hash)
            .emit(contract, "SponsorChanged").withArgs(TestDatas[9].hash, ethers.ZeroAddress, signers[15].address)
            .emit(contract, "DepositData").withArgs(signers[15].address, TestDatas[9].hash, ethers.parseEther("168000"), ethers.parseEther("42000"));
        
        expect(await contract.dataBalance(TestDatas[9].hash)).to.equal(ethers.parseEther("168000"));
        expect((await gwtToken.balanceOf(signers[15].address))).to.equal(ethers.parseEther("0"));
    });

    it("deposit data", async () => {
        await expect(contract.connect(signers[1]).addDeposit(TestDatas[0].hash, ethers.parseEther("100")))
            .emit(contract, "DepositData").withArgs(signers[1].address, TestDatas[0].hash, ethers.parseEther("80"), ethers.parseEther("20"));

        expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("694.4"));
    });

    it("deposit data failed", async () => {
        // prepare
        await expect(contract.connect(signers[14]).createPublicData(TestDatas[8].hash, 64, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .emit(contract, "PublicDataCreated").withArgs(TestDatas[8].hash)
            .emit(contract, "SponsorChanged").withArgs(TestDatas[8].hash, ethers.ZeroAddress, signers[14].address)
            .emit(contract, "DepositData").withArgs(signers[14].address, TestDatas[8].hash, ethers.parseEther("614.4"), ethers.parseEther("153.6"));
        
        expect(await contract.dataBalance(TestDatas[8].hash)).to.equal(ethers.parseEther("614.4"));
        expect((await contract.getPublicData(TestDatas[8].hash)).sponsor).to.equal(signers[14].address);

        // invalid hash
        await expect(contract.connect(signers[1]).addDeposit(ethers.ZeroHash, ethers.parseEther("100")))
            .to.be.revertedWith('public data not exist');

        // invalid amount
        await expect(contract.connect(signers[1]).addDeposit(ethers.ZeroHash, ethers.parseEther("0")))
            .to.be.reverted;

        // larger then balance
        await expect(contract.connect(signers[17]).addDeposit(TestDatas[8].hash, ethers.parseEther("210001")))
            .to.be.reverted;

        // little than 768 * 1.1
        await expect(contract.connect(signers[17]).addDeposit(TestDatas[8].hash, ethers.parseEther("844.7")))
            .emit(contract, "DepositData").withArgs(signers[17].address, TestDatas[8].hash, ethers.parseEther("675.76"), ethers.parseEther("168.94"));

        expect(await contract.dataBalance(TestDatas[8].hash)).to.equal(ethers.parseEther("1290.16"));
        expect((await contract.getPublicData(TestDatas[8].hash)).sponsor).to.equal(signers[14].address);

        // equal to maxAmount * 1.1
        // total amount larger than maxAmount * 1.1
        await expect(contract.connect(signers[17]).addDeposit(TestDatas[8].hash, ethers.parseEther("844.8")))
        .emit(contract, "DepositData").withArgs(signers[17].address, TestDatas[8].hash, ethers.parseEther("675.84"), ethers.parseEther("168.96"));

        expect(await contract.dataBalance(TestDatas[8].hash)).to.equal(ethers.parseEther("1966"));
        expect((await contract.getPublicData(TestDatas[8].hash)).sponsor).to.equal(signers[14].address);

        // larger to maxAmount * 1.1
        // total amount larger than maxAmount * 1.1
        await expect(contract.connect(signers[17]).addDeposit(TestDatas[8].hash, ethers.parseEther("844.9")))
        .emit(contract, "DepositData").withArgs(signers[17].address, TestDatas[8].hash, ethers.parseEther("675.92"), ethers.parseEther("168.98"));

        expect(await contract.dataBalance(TestDatas[8].hash)).to.equal(ethers.parseEther("2641.92"));
        expect((await contract.getPublicData(TestDatas[8].hash)).sponsor).to.equal(signers[17].address);
        
        // pay all
        // total amount larger than maxAmount * 1.1
        await expect(contract.connect(signers[17]).addDeposit(TestDatas[8].hash, ethers.parseEther("207465.6")))
        .emit(contract, "DepositData").withArgs(signers[17].address, TestDatas[8].hash, ethers.parseEther("165972.48"), ethers.parseEther("41493.12"));

        expect(await contract.dataBalance(TestDatas[8].hash)).to.equal(ethers.parseEther("168614.4"));
        expect((await contract.getPublicData(TestDatas[8].hash)).sponsor).to.equal(signers[17].address);
        expect((await gwtToken.balanceOf(signers[17].address))).to.equal(ethers.parseEther("0"));

        await (await dmcToken.transfer(await signers[17].address, ethers.parseEther("1"))).wait();
        await (await dmcToken.connect(signers[17]).approve(await gwtToken.getAddress(), ethers.parseEther("1"))).wait();
        await (await gwtToken.connect(signers[17]).exchange(ethers.parseEther("1"))).wait();
        await (await gwtToken.connect(signers[17]).approve(await contract.getAddress(), ethers.parseEther("210"))).wait();
        
        expect((await gwtToken.balanceOf(signers[17].address))).to.equal(ethers.parseEther("210"));
    });

    it("deposit data and became sponser", async () => {
        await expect(contract.connect(signers[1]).addDeposit(TestDatas[0].hash, ethers.parseEther("1000")))
            .emit(contract, "DepositData").withArgs(signers[1].address, TestDatas[0].hash, ethers.parseEther("800"), ethers.parseEther("200"))
            .emit(contract, "SponsorChanged").withArgs(TestDatas[0].hash, signers[0].address, signers[1].address);

            expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("1494.4"));
    });

    it("supplier pledge GWT", async () => {
        await (expect(contract.connect(signers[2]).pledgeGwt(ethers.parseEther("10000"))))
            .emit(contract, "SupplierBalanceChanged").withArgs(signers[2].address, ethers.parseEther("10000"), 0);

        await (expect(contract.connect(signers[3]).pledgeGwt(ethers.parseEther("10000"))))
            .emit(contract, "SupplierBalanceChanged").withArgs(signers[3].address, ethers.parseEther("10000"), 0);
    });

    async function showData(signer: HardhatEthersSigner): Promise<ContractTransactionResponse> {
        let nonce_block = await ethers.provider.getBlockNumber();
        await mine();

        let [min_index, path, leaf, proof] = await generateProof(TestDatas[0].data_file_path, nonce_block, TestDatas[0].merkle_file_path);
        let tx = contract.connect(signer).showData(TestDatas[0].hash, nonce_block, min_index, path, leaf);
        await expect(tx).emit(contract, "ShowDataProof").withArgs(signer.address, TestDatas[0].hash, nonce_block, min_index, proof);

        return tx;
    }

    it("show data", async () => {
        // 这个操作会锁定signers[2]的余额 1/8 GB * 24(周) * 64(倍) = 192 GWT
        let tx = await showData(signers[2]);
        await expect(tx).emit(contract, "SupplierBalanceChanged").withArgs(signers[2].address, ethers.parseEther("9808"), ethers.parseEther("192"));
            
    });

    it("show data on same block");

    it("show data again", async() => {
        await mine(720);

        let tx = await showData(signers[3]);
        await expect(tx)
            .emit(contract, "SupplierReward").withArgs(signers[2].address, TestDatas[0].hash, ethers.parseEther("149.44"))
            .emit(contract, "SupplierBalanceChanged").withArgs(signers[3].address, ethers.parseEther("9808"), ethers.parseEther("192"));

        // signers[2]得到奖励, 奖励从data[0]的余额里扣除
        // 得到的奖励：1494.4 * 0.1 * 0.8 = 119.552
        // 余额扣除：1494.4 * 0.1 = 149.44
        await expect(tx).changeTokenBalance(gwtToken, signers[2].address, ethers.parseEther("119.552"))
        expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("1344.96"));

        expect(await contract.getCurrectLastShowed(TestDatas[0].hash)).have.ordered.members([signers[2].address, signers[3].address, ethers.ZeroAddress, ethers.ZeroAddress, ethers.ZeroAddress]);
    });

    it("several suppliers show data", async () => {
        // 4, 5, 6, 7分别show这个数据
        for (let i = 4; i < 8; i++){
            await (expect(contract.connect(signers[i]).pledgeGwt(ethers.parseEther("10000"))))
                .emit(contract, "SupplierBalanceChanged").withArgs(signers[i].address, ethers.parseEther("10000"), 0);

            await mine(720);
            await showData(signers[i]);
        }
         
        expect(await contract.getCurrectLastShowed(TestDatas[0].hash)).have.ordered.members([signers[7].address, signers[3].address, signers[4].address, signers[5].address, signers[6].address]);
    });

    it("suppliers withdraw cycle reward", async () => {
        await mine(17280);

        // 奖池数量：373.6, 本期可分配：373.6 * 0.8 = 298.88
        // data[0]可分到298.88 * 240 / 1600 = 44.832
        // owner获得44.832*0.2=8.9664
        await expect(contract.connect(signers[0]).withdrawAward(1, TestDatas[0].hash))
            .changeTokenBalance(gwtToken, signers[0], ethers.parseEther("8.9664"));
        // sponser获得44.832*0.5 = 22.416
        await expect(contract.connect(signers[1]).withdrawAward(1, TestDatas[0].hash))
            .changeTokenBalance(gwtToken, signers[1], ethers.parseEther("22.416"));
        
        // signers3-7每人获得44.832*0.3/5 = 2.68992
        for (let index = 3; index <= 7; index++) {
            await expect(contract.connect(signers[index]).withdrawAward(1, TestDatas[0].hash))
                .changeTokenBalance(gwtToken, signers[index], ethers.parseEther("2.68992"));
        }
    });
});