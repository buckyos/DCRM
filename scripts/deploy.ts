import { ethers, network } from "hardhat";
import * as fs from "node:fs";

async function main() {
    const dmcContract = await (await ethers.deployContract("DMCToken", [ethers.parseEther("1000000")])).waitForDeployment();
    let dmcAddress = await dmcContract.getAddress();
    console.log("DMCToken deployed to:", dmcAddress);
    const gwtContract = await (await ethers.deployContract("GWTToken", [dmcAddress])).waitForDeployment();

    let gwtAddress = await gwtContract.getAddress();
    console.log("GWT deployed to:", gwtAddress);
    /*
    const exchangeContract = await (await ethers.deployContract("StorageExchange", [gwtAddress])).waitForDeployment();
    let exchangeAddress = await exchangeContract.getAddress();
    console.log("Exchange deployed to:", exchangeAddress);
    */
    const sortedScoreList = await (await ethers.deployContract("SortedScoreList")).waitForDeployment();
    let sortedScoreListAddress = await sortedScoreList.getAddress();
    console.log("SortedScoreList deployed to:", sortedScoreListAddress);
    const publicDataStorage = await (await ethers.deployContract("PublicDataStorage", [gwtAddress], {libraries: {"SortedScoreList": sortedScoreListAddress}})).waitForDeployment();
    let publicDataStorageAddress = await publicDataStorage.getAddress();
    console.log("PublicDataStorage deployed to:", publicDataStorageAddress);

    await(await gwtContract.enableTransfer([publicDataStorageAddress])).wait();

    if (network.name !== "hardhat") {
        fs.writeFileSync(`${network.name}-deployed.json`, JSON.stringify({
            DMCToken: dmcAddress,
            GWTToken: gwtAddress,
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
