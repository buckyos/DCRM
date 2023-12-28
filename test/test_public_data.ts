import hre, { ethers } from "hardhat";
import { expect } from "chai";
import { DMCToken, FakeNFTContract, GWTToken, PublicDataStorage } from "../typechain-types";

import * as TestDatas from "../testDatas/test_data.json";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

import { generateProof } from "../scripts/generate_proof";

describe("PublicDataStorage", function () {
    let contract: PublicDataStorage;
    let dmcToken: DMCToken;
    let gwtToken: GWTToken;
    let signers: HardhatEthersSigner[];
    let nftContract: FakeNFTContract

    async function deployContracts() {
        let listLibrary = await (await hre.ethers.getContractFactory("SortedScoreList")).deploy();

        dmcToken = await (await ethers.deployContract("DMCToken", [ethers.parseEther("10000000")])).waitForDeployment()
        gwtToken = await (await ethers.deployContract("GWTToken", [await dmcToken.getAddress()])).waitForDeployment()

        // nftContract = await (await hre.ethers.deployContract("FakeNFTContract")).waitForDeployment();
        contract = await (await hre.ethers.deployContract("PublicDataStorage", [await gwtToken.getAddress()], {libraries: {
            SortedScoreList: await listLibrary.getAddress()
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

    it("show data", async () => {
        let nonce_block = await ethers.provider.getBlockNumber();
        await mine();

        let [min_index, path, leaf, proof] = await generateProof(TestDatas[0].data_file_path, nonce_block, TestDatas[0].merkle_file_path);

        // 这个操作会锁定signers[2]的余额 1/8 GB * 24(周) * 64(倍) = 192 GWT
        await expect(contract.connect(signers[2]).showData(TestDatas[0].hash, nonce_block, min_index, path, leaf))
            .emit(contract, "ShowDataProof").withArgs(signers[2].address, TestDatas[0].hash, nonce_block, min_index, proof)
            .emit(contract, "SupplierBalanceChanged").withArgs(signers[2].address, ethers.parseEther("9808"), ethers.parseEther("192"));
    });

    it("show data on same block");

    it("show data again", async() => {
        await mine(720);

        let nonce_block = await ethers.provider.getBlockNumber();
        await mine();
        let [min_index, path, leaf, proof] = await generateProof(TestDatas[0].data_file_path, nonce_block, TestDatas[0].merkle_file_path);
        let tx = contract.connect(signers[3]).showData(TestDatas[0].hash, nonce_block, min_index, path, leaf);
        await expect(tx)
            .emit(contract, "SupplierReward").withArgs(signers[2].address, TestDatas[0].hash, ethers.parseEther("149.44"))
            .emit(contract, "ShowDataProof").withArgs(signers[3].address, TestDatas[0].hash, nonce_block, min_index, proof)
            .emit(contract, "SupplierBalanceChanged").withArgs(signers[3].address, ethers.parseEther("9808"), ethers.parseEther("192"));

        // signers[1]得到奖励, 奖励从data[0]的余额里扣除
        // 得到的奖励：1494.4 * 0.1 * 0.8 = 119.552
        // 余额扣除：1494.4 * 0.1 = 149.44
        await expect(tx).changeTokenBalance(gwtToken, signers[2].address, ethers.parseEther("119.552"))
            
        
        expect(await contract.dataBalance(TestDatas[0].hash)).to.equal(ethers.parseEther("1344.96"));
    });
});