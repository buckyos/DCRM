import { ethers, upgrades } from "hardhat";
const DIVIDEND_ADDRESS = "0xD1AB647a6D3163bAD9D5C49C8A23Ee2811FC9e50"

async function main() {
    console.log("upgrading DividendContract...");
    (await upgrades.upgradeProxy(DIVIDEND_ADDRESS, await ethers.getContractFactory("DividendContract"), {
        kind: "uups",
        timeout: 0
    })).waitForDeployment();
}

main().then(() => {
    process.exit(0);
});