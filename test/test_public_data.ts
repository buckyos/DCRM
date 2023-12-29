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
        contract = await (await ethers.deployContract("PublicDataStorage", [await gwtToken.getAddress()], {libraries: {
            SortedScoreList: await listLibrary.getAddress(),
            PublicDataProof: await proofLibrary.getAddress()
        }})).waitForDeployment();

        await (await gwtToken.enableTransfer([await contract.getAddress()])).wait();
    }

    before(async () => {
        await deployContracts();

        signers = await ethers.getSigners()

        for (const signer of signers) {
            await (await dmcToken.transfer(await signer.address, ethers.parseEther("1000"))).wait();
            await (await dmcToken.connect(signer).approve(await gwtToken.getAddress(), ethers.parseEther("1000"))).wait();
            await (await gwtToken.connect(signer).exchange(ethers.parseEther("1000"))).wait();
            await (await gwtToken.connect(signer).approve(await contract.getAddress(), ethers.parseEther("210000"))).wait();
        }
    });

    it("create public data", async () => {
        // 需要的最小抵押：1/8 GB * 96(周) * 64(倍) = 768 GWT
        await expect(contract.createPublicData(TestDatas[0].hash, 64, ethers.parseEther("768"), ethers.ZeroAddress, 0))
            .emit(contract, "PublicDataCreated").withArgs(TestDatas[0].hash)
            .emit(contract, "SponsorChanged").withArgs(TestDatas[0].hash, ethers.ZeroAddress, signers[0].address)
            .emit(contract, "DepositData").withArgs(signers[0].address, TestDatas[0].hash, ethers.parseEther("614.4"), ethers.parseEther("153.6"));

        expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("614.4"));
    });

    it("deposit data", async () => {
        await expect(contract.connect(signers[1]).addDeposit(TestDatas[0].hash, ethers.parseEther("100")))
            .emit(contract, "DepositData").withArgs(signers[1].address, TestDatas[0].hash, ethers.parseEther("80"), ethers.parseEther("20"));

        expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("694.4"));
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
        console.log(`signer 0 ${signers[0].address} will withdraw in ts:`);
        await expect(contract.connect(signers[0]).withdrawAward(1, TestDatas[0].hash))
            .changeTokenBalance(gwtToken, signers[0], ethers.parseEther("8.9664"));
        // sponser获得44.832*0.5 = 22.416
        console.log(`signer 1 ${signers[1].address} will withdraw in ts:`);
        await expect(contract.connect(signers[1]).withdrawAward(1, TestDatas[0].hash))
            .changeTokenBalance(gwtToken, signers[1], ethers.parseEther("22.416"));
        
        // signers3-7每人获得44.832*0.3/5 = 2.68992
        for (let index = 3; index <= 7; index++) {
            console.log(`signer ${index} ${signers[index].address} will withdraw in ts:`);
            await expect(contract.connect(signers[index]).withdrawAward(1, TestDatas[0].hash))
                .changeTokenBalance(gwtToken, signers[index], ethers.parseEther("2.68992"));
        }
    });
});