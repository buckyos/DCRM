import hre, { ethers } from "hardhat";
import { expect } from "chai";
import { FakeNFTContract, GWTToken, PublicDataStorage } from "../typechain-types";

// 需要一个假的NFT合约，用来测试
// 给这个假NFT合约放1个NFT进去
// owner signer[0]

// 让signer[0]通过NFT创建一个public data，检查数据账户余额和奖池余额
// 让signer[1]在错误的块上show数据，应该会失败
// 让signer[1]show数据，检查signer[1]余额和数据账户余额
// 尝试在同一块内让signer[1]再次show数据，此处应该失败
// 让signer[11]增加质押金，成为Data1的sponser
// 让signer[2]到[7]都show数据，确定last_shower正确
// 前进到当前cycle结束
// signer[12]通过普通数据创建一个public data，检查此轮的奖池余额是否正确
// signer[0]将NFT的owner转移给signer[13]
// signer[0]提取奖金，应该会失败
// signer[11], signer[12], signer[3-7]提取奖金，检查提取的余额是否正确

describe("PublicDataStorage", function () {
    let contract: PublicDataStorage;
    let gwtToken: GWTToken;
    let nftContract: FakeNFTContract
    async function deployContracts() {
        let listLibrary = await (await hre.ethers.getContractFactory("SortedScoreList")).deploy();
        
        gwtToken = await (await hre.ethers.deployContract("GWTToken", [ethers.parseEther("100000000")])).waitForDeployment();

        nftContract = await (await hre.ethers.deployContract("FakeNFTContract")).waitForDeployment();

//        contract = await (await hre.ethers.deployContract("PublicDataStorage", {libraries: {
//            SortedScoreList: await listLibrary.getAddress()
//        }})).waitForDeployment();
    }

    before(async () => {
        await deployContracts();

//        await ((await nftContract.addData("", 1)).wait());
    });

    it("create NFT public data");

    it("show data on wrong block");

    it("show data");

    it("show data twice on same block");

    it("change sponser");

    it("several people show data");

    it("forward to next cycle");

    it("create normal public data");

    it("change NFT owner");

    it("wrong people withdraw reward");

    it("several people withdraw reward");
});