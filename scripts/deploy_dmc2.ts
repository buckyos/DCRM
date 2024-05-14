import { ethers, upgrades } from "hardhat";
import { DividendContract, Exchange } from "../typechain-types";

async function main() {
    let signers = await ethers.getSigners();
    let dmc = await (await ethers.deployContract("DMC", [
        ethers.parseEther("1000000000"),                    // 总量10亿
        ["0x000000000EefEA4e8A67d7434a02054b955Da62c", "0xDDDDDdDd91f172a0ceA030d20f68348E0370fE66", "0xCcCCCCCC5b74A876dB192d55ef8e4A60EfA1Eb5C", "0xad82A5fb394a525835A3a6DC34C1843e19160CFA"],
        [ethers.parseEther("450000000"), ethers.parseEther("4500000"), ethers.parseEther("45000000"), ethers.parseEther("500000")]])).waitForDeployment()

    let dmcAddress = await dmc.getAddress();
    console.log("DMC address:", dmcAddress);

    let gwt = await (await ethers.deployContract("GWT", [[], []])).waitForDeployment();
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
        [await dmc.getAddress(), await gwt.getAddress(), dividendAddress, 7 * 24 * 60 * 60],
        {
            initializer: "initialize",
            kind: "uups",
            timeout: 0
        })).waitForDeployment() as unknown as Exchange;
    let exchangeAddr = await exchange.getAddress();
    console.log("exchange address:", exchangeAddr);

    console.log("enable mint");

    await (await dmc.enableMinter([exchangeAddr])).wait();
    await (await gwt.enableMinter([exchangeAddr])).wait();
}

main().then(() => process.exit(0));