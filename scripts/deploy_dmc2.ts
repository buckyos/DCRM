import { ethers, upgrades } from "hardhat";
import { DividendContract, Exchange } from "../typechain-types";

/*
DMC address: 0x05F2E406606f82Ec96DcE822B295278795c5053B
GWT address: 0x191Af8663fF88823d6b226621DC4700809D042fa
Dividend address: 0xD1AB647a6D3163bAD9D5C49C8A23Ee2811FC9e50
exchange address: 0x785423901A501Bcef29Ab2a8cAFa25D5a8c027d3
Layer1 DMC Address: 0x910e888698dA0C2eCC97A04A137Aa1CfC1Dfd209
*/

async function main() {
    let dmc = await (await ethers.deployContract("DMC", [
        ethers.parseEther("1000000000"),                    // 总量10亿
        ["0x000000000EefEA4e8A67d7434a02054b955Da62c", "0xDDDDDdDd91f172a0ceA030d20f68348E0370fE66", "0xCcCCCCCC5b74A876dB192d55ef8e4A60EfA1Eb5C", "0xad82A5fb394a525835A3a6DC34C1843e19160CFA"],
        [ethers.parseEther("450000000"), ethers.parseEther("4500000"), ethers.parseEther("45000000"), ethers.parseEther("500000")]])).waitForDeployment()

    let dmcAddress = await dmc.getAddress();
    console.log("DMC address:", dmcAddress);

    let gwt = await (await ethers.deployContract("GWT", [["0xad82A5fb394a525835A3a6DC34C1843e19160CFA"], [ethers.parseEther("5000000")]])).waitForDeployment();
    let gwtAddress = await gwt.getAddress();
    console.log("GWT address:", gwtAddress);

    let dividend = (await (
        await upgrades.deployProxy(
            await ethers.getContractFactory("DividendContract"),
            [dmcAddress, 7 * 24 * 60 * 60, [gwtAddress, ethers.ZeroAddress]],
            {
                initializer: "initialize",
                kind: "uups",
                timeout: 0
            }
        )
    ).waitForDeployment()) as unknown as DividendContract;

    let dividendAddress = await dividend.getAddress();
    console.log("Dividend address:", dividendAddress);

    let exchange = await (await upgrades.deployProxy(await ethers.getContractFactory("Exchange"),
        [await dmc.getAddress(), gwtAddress, dividendAddress, 7 * 24 * 60 * 60],
        {
            initializer: "initialize",
            kind: "uups",
            timeout: 0
        })).waitForDeployment() as unknown as Exchange;
    let exchangeAddr = await exchange.getAddress();
    console.log("exchange address:", exchangeAddr);

    let pst = await (await ethers.deployContract("PSTBridge", [gwtAddress])).waitForDeployment();
    let pstAddress = await pst.getAddress();
    console.log("PSTBridge address:", pstAddress);

    console.log("enable mint");

    await (await dmc.enableMinter([exchangeAddr])).wait();
    await (await gwt.enableMinter([exchangeAddr, pstAddress])).wait();
}

main().then(() => process.exit(0));