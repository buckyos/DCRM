import { ethers, network, upgrades } from "hardhat";
import * as fs from "node:fs";
import { Exchange, PublicDataStorage } from "../typechain-types";

let depolyedInfo: any = {};

if (fs.existsSync(`${network.name}-deployed.json`)) {
    depolyedInfo = JSON.parse(fs.readFileSync(`${network.name}-deployed.json`, { encoding: 'utf-8' }));
}

function saveInfo() {
    fs.writeFileSync(`${network.name}-deployed.json`, JSON.stringify(depolyedInfo, null, 4));
}

export async function main() {
    // 部署DMC合约，精度18，最大值10亿
    // 基金会账户初始分配15W
    let foundationAddress = "0x846cc73d43bda4bcd57cb23678b31f2bf24f801a";
    // for test:
    let depolyAddr = (await ethers.getSigners())[0].address;
    if (network.name === "localhost") {
        foundationAddress = (await ethers.getSigners())[19].address;
        console.log("depoly address:", depolyAddr);
    }

    let dmcContract;

    if (!depolyedInfo.DMCToken) {
        console.log("Deploying DMC...");
        dmcContract = await (await ethers.deployContract("DMCToken", [ethers.parseEther("1000000000"), [], []])).waitForDeployment();
        depolyedInfo.DMCToken = await dmcContract.getAddress();
        saveInfo();
    } else {
        console.log("DMC already deployed, address", depolyedInfo.DMCToken);
        dmcContract = await ethers.getContractAt("DMCToken", depolyedInfo.DMCToken);
    }

    let gwtContract;
    
    if (!depolyedInfo.GWTToken) {
        // 部署GWT合约
        console.log("Deploying GWT...");
        gwtContract = await (await ethers.deployContract("GWTToken")).waitForDeployment();
        depolyedInfo.GWTToken = await gwtContract.getAddress();
        saveInfo();
    } else {
        console.log("GWT already deployed, address", depolyedInfo.GWTToken);
        gwtContract = await ethers.getContractAt("GWTToken", depolyedInfo.GWTToken);
    }

    let luckyMint;
    
    if (!depolyedInfo.LuckyMint) {
        console.log("Deploying LuckyMint...");
        luckyMint = await (await ethers.deployContract("LuckyMint")).waitForDeployment();
        depolyedInfo.LuckyMint = await luckyMint.getAddress();
        saveInfo();
    } else {
        console.log("LuckyMint already deployed, address", depolyedInfo.LuckyMint);
        luckyMint = await ethers.getContractAt("LuckyMint", depolyedInfo.LuckyMint);
    }

    let exchange;
    
    if (!depolyedInfo.exchange) {
        // 部署兑换合约
        console.log("Deploying Exchange...");
        exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"),
            [depolyedInfo.DMCToken, depolyedInfo.GWTToken],
            {
                initializer: "initialize",
                kind: "uups",
                timeout: 0
            })).waitForDeployment() as unknown as Exchange;
        depolyedInfo.exchange = await exchange.getAddress();
        saveInfo();
    } else {
        console.log("Exchange already deployed, address", depolyedInfo.exchange);
        exchange = await ethers.getContractAt("Exchange", depolyedInfo.exchange);
    }

    console.log("set token minter...");
    await (await dmcContract.enableMinter([depolyedInfo.exchange])).wait();
    await (await gwtContract.enableMinter([depolyedInfo.exchange])).wait();

    // 部署公共数据合约的库合约
    if (!depolyedInfo.listLibrary) {
        console.log("Depoly SortedList Library...");
        let listLibrary = await (await ethers.getContractFactory("SortedScoreList")).deploy();
        depolyedInfo.listLibrary = await listLibrary.getAddress();
        saveInfo();
    } else {
        console.log("SortedList Library already deployed, address", depolyedInfo.listLibrary);
    }

    if (!depolyedInfo.proofLibrary) {
        console.log("Depoly PublicDataProof Library...");
        let proofLibrary = await (await ethers.getContractFactory("PublicDataProof")).deploy();
        depolyedInfo.proofLibrary = await proofLibrary.getAddress();
        saveInfo();
    } else {
        console.log("PublicDataProof Library already deployed, address", depolyedInfo.proofLibrary);
    }

    let publicDataStorage;

    if (!depolyedInfo.PublicDataStore) {
        console.log("Depoly PublicDataStorage...");
        publicDataStorage = await (await upgrades.deployProxy(await ethers.getContractFactory("PublicDataStorage", {
            libraries: {
                "SortedScoreList": depolyedInfo.listLibrary,
                "PublicDataProof": depolyedInfo.proofLibrary
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
        saveInfo();
    } else {
        console.log("PublicDataStorage already deployed, address", depolyedInfo.PublicDataStore);
        publicDataStorage = await ethers.getContractAt("PublicDataStorage", depolyedInfo.PublicDataStore);
    }

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
        await (await publicDataStorage.allowPublicDataContract([await bridge.getAddress()])).wait()
        depolyedInfo.Bridge = await bridge.getAddress();
        saveInfo();
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
