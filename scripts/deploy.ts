import { ethers, network, upgrades } from "hardhat";
import * as fs from "node:fs";
import { Exchange, PublicDataStorage } from "../typechain-types";

async function main() {
    const dmcContract = await (await ethers.deployContract("DMCToken", [ethers.parseEther("100000000")])).waitForDeployment();
    let dmcAddress = await dmcContract.getAddress();
    console.log("DMCToken deployed to:", dmcAddress);
    const gwtContract = await (await ethers.deployContract("GWTToken")).waitForDeployment();

    let gwtAddress = await gwtContract.getAddress();
    console.log("GWT deployed to:", gwtAddress);

    let exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"), 
            [dmcAddress, gwtAddress], 
            {
                initializer: "initialize",
                kind: "uups",
                timeout: 0
            })).waitForDeployment() as unknown as Exchange;
    
    let listLibrary = await (await ethers.getContractFactory("SortedScoreList")).deploy();
    let proofLibrary = await (await ethers.getContractFactory("PublicDataProof")).deploy();

    let foundationAddress = (await ethers.getSigners())[19].address;
    
    const publicDataStorage = await (await ethers.deployContract("PublicDataStorage", [gwtAddress, foundationAddress], {libraries: {
        "SortedScoreList": await listLibrary.getAddress(),
        "PublicDataProof": await proofLibrary.getAddress()
    }})).waitForDeployment();
    
    let publicDataStorageAddress = await publicDataStorage.getAddress();
    console.log("PublicDataStorage deployed to:", publicDataStorageAddress);

    await (await gwtContract.enableMinter([await exchange.getAddress()])).wait();

    await(await gwtContract.enableTransfer([publicDataStorageAddress])).wait();

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
            minDataSize: config.minDataSize
        };
        setConfig.showTimeout = 720n;
        setConfig.lockAfterShow = 720n;
        setConfig.minRankingScore = 1n;
        await (await publicDataStorage.setSysConfig(setConfig)).wait();

    if (network.name !== "hardhat") {
        fs.writeFileSync(`${network.name}-deployed.json`, JSON.stringify({
            DMCToken: dmcAddress,
            GWTToken: gwtAddress,
            exchange: await exchange.getAddress(),
            PublicDataStore: publicDataStorageAddress
        }));
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
