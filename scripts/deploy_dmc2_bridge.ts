import { ethers, upgrades } from "hardhat";
import { DividendContract, Exchange } from "../typechain-types";

/*
DMC address: 0x05F2E406606f82Ec96DcE822B295278795c5053B
GWT address: 0x191Af8663fF88823d6b226621DC4700809D042fa
Dividend address: 0xD1AB647a6D3163bAD9D5C49C8A23Ee2811FC9e50
exchange address: 0x785423901A501Bcef29Ab2a8cAFa25D5a8c027d3
Layer1 DMC Address: 0x910e888698dA0C2eCC97A04A137Aa1CfC1Dfd209

DMCBridge address: 0x30EeEF94C7cfb7CC2b3BF8F6a2376ec187A95E8d
PSTBridge address: 0xaaA6DbB71fF0d2CC8E421A94B0778e51b4760f11
*/

async function main() {
    let dmc = await (await ethers.deployContract("DMCBridge", ["0x05F2E406606f82Ec96DcE822B295278795c5053B"])).waitForDeployment()

    let dmcAddress = await dmc.getAddress();
    console.log("DMCBridge address:", dmcAddress);

    let pst = await (await ethers.deployContract("PSTBridge", ["0x191Af8663fF88823d6b226621DC4700809D042fa"])).waitForDeployment();
    let pstAddress = await pst.getAddress();
    console.log("PSTBridge address:", pstAddress);

    let gwt = await ethers.getContractAt("GWT", "0x191Af8663fF88823d6b226621DC4700809D042fa");

    await (await gwt.enableMinter([pstAddress])).wait();
}

main().then(() => process.exit(0));