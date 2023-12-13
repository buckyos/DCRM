import { ethers, network } from "hardhat";
import * as fs from "node:fs";

async function main() {
    const pstContract = await (await ethers.deployContract("GWTToken", [ethers.parseEther("1000000")])).waitForDeployment();

    let pstAddress = await pstContract.getAddress();
    console.log("GWT deployed to:", pstAddress);

    const exchangeContract = await (await ethers.deployContract("StorageExchange", [pstAddress])).waitForDeployment();
    let exchangeAddress = await exchangeContract.getAddress();
    console.log("Exchange deployed to:", exchangeAddress);

    if (network.name !== "hardhat") {
        fs.writeFileSync(`${network.name}-deployed.json`, JSON.stringify({
            PSTToken: pstAddress,
            StorageExchange: exchangeAddress
        }));
    }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
