import { ethers } from "hardhat";

async function main() {
    const pstContract = await (await ethers.deployContract("PSTToken", [ethers.parseEther("1000000")])).waitForDeployment();

    let pstAddress = await pstContract.getAddress();
    console.log("PST deployed to:", pstAddress);

    const exchangeContract = await (await ethers.deployContract("StorageExchange", [pstAddress])).waitForDeployment();

    console.log("Exchange deployed to:", await exchangeContract.getAddress());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
