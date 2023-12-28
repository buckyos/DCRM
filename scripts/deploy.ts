import { ethers, network } from "hardhat";
import * as fs from "node:fs";

async function main() {
    const dmcContract = await (await ethers.deployContract("DMCToken", [ethers.parseEther("100000000")])).waitForDeployment();
    let dmcAddress = await dmcContract.getAddress();
    console.log("DMCToken deployed to:", dmcAddress);
    const gwtContract = await (await ethers.deployContract("GWTToken", [dmcAddress])).waitForDeployment();

    let gwtAddress = await gwtContract.getAddress();
    console.log("GWT deployed to:", gwtAddress);
    
    let listLibrary = await (await ethers.getContractFactory("SortedScoreList")).deploy();
    let proofLibrary = await (await ethers.getContractFactory("PublicDataProof")).deploy();

    
    const publicDataStorage = await (await ethers.deployContract("PublicDataStorage", [gwtAddress], {libraries: {
        "SortedScoreList": await listLibrary.getAddress(),
        "PublicDataProof": await proofLibrary.getAddress()
    }})).waitForDeployment();
    
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
