import { ethers, network, upgrades } from "hardhat";
import * as fs from "node:fs";
import { Exchange, PublicDataStorage } from "../typechain-types";

async function main() {
    let depolyedInfo: any = {};
    // 部署DMC合约，精度18，最大值10亿
    // 基金会账户初始分配15W
    // TODO：基金会账户地址？
    let foundationAddress = "";
    // for test:
    if (network.name === "localhost") {
        foundationAddress = (await ethers.getSigners())[19].address;
    }
    console.log("Deploying DMC...");
    const dmcContract = await (await ethers.deployContract("DMCToken", [ethers.parseEther("1000000000"), [foundationAddress], [ethers.parseEther("150000")]])).waitForDeployment();
    depolyedInfo.DMCToken = await dmcContract.getAddress();
    // 部署GWT合约
    console.log("Deploying GWT...");
    const gwtContract = await (await ethers.deployContract("GWTToken")).waitForDeployment();
    depolyedInfo.GWTToken = await gwtContract.getAddress();

    console.log("Deploying LuckyMint...");
    const luckyMint = await (await ethers.deployContract("LuckyMint")).waitForDeployment();
    depolyedInfo.LuckyMint = await luckyMint.getAddress();

    // 部署兑换合约
    console.log("Deploying Exchange...");
    let exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"),
        [depolyedInfo.DMCToken, depolyedInfo.GWTToken],
        {
            initializer: "initialize",
            kind: "uups",
            timeout: 0
        })).waitForDeployment() as unknown as Exchange;
    depolyedInfo.exchange = await exchange.getAddress();

    console.log("set minter...");
    await (await dmcContract.enableMinter([await exchange.getAddress()])).wait();
    await (await gwtContract.enableMinter([await exchange.getAddress()])).wait();
    // TODO: 处理allowMintDMC的权限问题

    // 部署公共数据合约的库合约
    console.log("Depoly Library...");
    let listLibrary = await (await ethers.getContractFactory("SortedScoreList")).deploy();
    let proofLibrary = await (await ethers.getContractFactory("PublicDataProof")).deploy();

    console.log("Depoly PublicDataStorage...");
    //let foundationAddress = (await ethers.getSigners())[19].address;
    const publicDataStorage = await (await upgrades.deployProxy(await ethers.getContractFactory("PublicDataStorage", {
        libraries: {
            "SortedScoreList": await listLibrary.getAddress(),
            "PublicDataProof": await proofLibrary.getAddress()
        }
    }),
        [depolyedInfo.GWTToken, foundationAddress],
        {
            initializer: "initialize",
            kind: "uups",
            timeout: 0,
            unsafeAllow: ["external-library-linking"],
        })).waitForDeployment();
    depolyedInfo.PublicDataStore = await publicDataStorage.getAddress();

    console.log("GWT enable transfer to publicDataStorage...");
    await (await gwtContract.enableTransfer([depolyedInfo.PublicDataStore])).wait();
    // for test
    if (network.name == "localhost") {
        await (await exchange.allowMintDMC([(await ethers.getSigners())[0].address], ["dmc_for_test"], [ethers.parseEther("100000000")])).wait();
        await (await exchange.mintDMC("dmc_for_test")).wait();

        let config = await publicDataStorage.sysConfig();
        let setConfig: PublicDataStorage.SysConfigStruct = {
            minDepositRatio: config.minDepositRatio,
            minPublicDataStorageWeeks: config.minPublicDataStorageWeeks,
            minLockWeeks: config.minLockWeeks,
            blocksPerCycle: config.blocksPerCycle,
            topRewards: config.topRewards,
            lockAfterShow: config.lockAfterShow,
            showTimeout: config.showTimeout,
            maxNonceBlockDistance: config.maxNonceBlockDistance,
            minRankingScore: config.minRankingScore,
            minDataSize: config.minDataSize,
            createDepositRatio: config.createDepositRatio,
        };
        setConfig.showTimeout = 720n;
        setConfig.lockAfterShow = 720n;
        setConfig.minRankingScore = 1n;
        await (await publicDataStorage.setSysConfig(setConfig)).wait();

        let bridge = await (await ethers.getContractFactory("OwnedNFTBridge")).deploy();
        await (await publicDataStorage.allowPublicDataContract(await bridge.getAddress())).wait()
        depolyedInfo.Bridge = await bridge.getAddress();
    }

    if (network.name !== "hardhat") {
        fs.writeFileSync(`${network.name}-deployed.json`, JSON.stringify(depolyedInfo, null, 4));
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
