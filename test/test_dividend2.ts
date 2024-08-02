import { ethers, upgrades } from "hardhat";
import { DMC, GWT, DividendContract } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { assert, expect } from "chai";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

describe("Devidend", function () {
    let dmc: DMC;
    let gwt: GWT;
    //let dividend: Dividend2;
    let dividend: DividendContract;
    let signers: HardhatEthersSigner[];

    before(async () => {
        signers = await ethers.getSigners();

        dmc = await (
            await ethers.deployContract("DMC", [
                ethers.parseEther("1000000000"),
                [signers[0].address],
                [1000000],
            ])
        ).waitForDeployment();
        gwt = await (await ethers.deployContract("GWT", [[],[]])).waitForDeployment();
        //dividend = await (await ethers.deployContract("Dividend2", [await dmc.getAddress(), 1000])).waitForDeployment()

        // add init token address as white list, address(0) and gwt token address
        const tokenWhiteList = [
            await gwt.getAddress(),
            "0x0000000000000000000000000000000000000000",
        ];

        const proposalContract = "0x0000000000000000000000000000000000000000";

        dividend = (await (
            await upgrades.deployProxy(
                await ethers.getContractFactory("DividendContract"),
                [await dmc.getAddress(), 1000, tokenWhiteList, 0, proposalContract]
            )
        ).waitForDeployment()) as unknown as DividendContract;

        // 给signers[0] 1000个GWT
        await (await gwt.enableMinter([signers[0].address])).wait();
        await (await gwt.mint(signers[0].address, 10000)).wait();
        await (await gwt.approve(await dividend.getAddress(), 10000)).wait();

        // 给signers[1]到19, 每人100个DMC
        for (let i = 1; i < 3; i++) {
            await (await dmc.transfer(signers[i].address, 100)).wait();
            await (
                await dmc.connect(signers[i]).approve(await dividend.getAddress(), 1000)
            ).wait();
        }

        // 测试白名单
        await (await dividend.addTokenToWhitelist(await gwt.getAddress())).wait();
    });

    it("test init", async () => {
        // test white list, only owner can add token to white list
        dividend.connect(signers[0]).addTokenToWhitelist(await gwt.getAddress());

        // test not owner
        await expect(
            dividend.connect(signers[1]).addTokenToWhitelist(await gwt.getAddress())
        ).to.be.reverted;

        // test remove token from white list
        await (
            await dividend.removeTokenFromWhitelist(await gwt.getAddress())
        ).wait();

        // test is in white list
        expect(
            await dividend.isTokenInWhitelisted(await gwt.getAddress())
        ).to.equal(false);

        // add again
        await (await dividend.addTokenToWhitelist(await gwt.getAddress())).wait();
        expect(
            await dividend.isTokenInWhitelisted(await gwt.getAddress())
        ).to.equal(true);

        // display the white list
        const whiteList = await dividend.getTokenWhitelist();
        console.log("white list: ", whiteList);
    });

    it("test cycle 0", async () => {
        // 初始周期0
        expect(await dividend.getCurrentCycleIndex()).to.equal(0);
        await dividend.tryNewCycle();
        expect(await dividend.getCurrentCycleIndex()).to.equal(0);

        // error unstake and withdraw test
        await expect(dividend.connect(signers[1]).unstake(50)).to.be.revertedWith(
            "No stake record found"
        );
        await expect(
            dividend
                .connect(signers[1])
                .withdrawDividends([0], [await gwt.getAddress()])
        ).to.be.revertedWith("Cannot claim current or future cycle");

        await expect(dividend.connect(signers[0]).unstake(50)).to.be.revertedWith(
            "No stake record found"
        );
        await expect(
            dividend
                .connect(signers[0])
                .withdrawDividends([0, 1, 2], [await gwt.getAddress()])
        ).to.be.revertedWith("Cannot claim current or future cycle");

        // test getStakeAmount with signer[0]
        expect(await dividend.connect(signers[0]).getStakeAmount(0)).to.equal(0);
        await expect(
            dividend.connect(signers[0]).getStakeAmount(1)
        ).to.be.revertedWith("Invalid cycle index");

        await expect(
            dividend.connect(signers[1]).getStakeAmount(10)
        ).to.be.revertedWith("Invalid cycle index");
    });

    it("test cycle 1", async () => {
        mine(2, { interval: 1000 });
        expect(await dividend.getCurrentCycleIndex()).to.equal(0);

        {
            // check the token balance is 0
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                0
            );

            // 打入100 GWT, 前进到周期1
            await (await dividend.deposit(90, await gwt.getAddress())).wait();

            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                90
            );

            // direct transfer to dividend contract
            await (await gwt.transfer(await dividend.getAddress(), 10)).wait();
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                100
            );
        }

        expect(await dividend.getCurrentCycleIndex()).to.equal(1);

        // check stake amount with signer[1]
        expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
        expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(0);
        await expect(
            dividend.connect(signers[1]).getStakeAmount(2)
        ).to.be.revertedWith("Invalid cycle index");

        // 第1周期，signers1，2分别stake 50 DMC
        await (await dividend.connect(signers[1]).stake(50)).wait();
        await (await dividend.connect(signers[2]).stake(50)).wait();

        // check dmc balance for signer[1] and signer[2]
        expect(await dmc.balanceOf(signers[1].address)).to.equal(50);
        expect(await dmc.balanceOf(signers[2].address)).to.equal(50);

        expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
        expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(50);
        expect(await dividend.connect(signers[2]).getStakeAmount(0)).to.equal(0);
        expect(await dividend.connect(signers[2]).getStakeAmount(1)).to.equal(50);
        await expect(
            dividend.connect(signers[2]).getStakeAmount(2)
        ).to.be.revertedWith("Invalid cycle index");

        // test withdraw dividends with cycle 0
        await (
            await dividend
                .connect(signers[1])
                .withdrawDividends([0], [await gwt.getAddress()])
        ).wait();
        expect(await gwt.balanceOf(signers[1].address)).to.equal(0);

        // test withdraw dividends with cycle 1 with revert
        await expect(
            dividend
                .connect(signers[1])
                .withdrawDividends([1], [await gwt.getAddress()])
        ).to.be.revertedWith("Cannot claim current or future cycle");

        await expect(
            dividend
                .connect(signers[1])
                .withdrawDividends([2], [await gwt.getAddress()])
        ).to.be.revertedWith("Cannot claim current or future cycle");

        // test withdraw dividends with unknown tokens
        // nothing to withdraw
        await (
            await dividend
                .connect(signers[1])
                .withdrawDividends([0], [await signers[1].address])
        ).wait();
    });

    it("test cycle 2", async () => {
        // 又打入100 GWT，前进到周期2, 此时总分红200 GWT，因为周期1没有完整的抵押，所以周期1的分红是提不到的
        mine(2, { interval: 1000 });
        await (await dividend.deposit(100, await gwt.getAddress())).wait();

        // check stake amount with signer[1] and signer[2]
        expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
        expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(50);
        expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(50);

        expect(await dividend.connect(signers[2]).getStakeAmount(0)).to.equal(0);
        expect(await dividend.connect(signers[2]).getStakeAmount(1)).to.equal(50);
        expect(await dividend.connect(signers[2]).getStakeAmount(2)).to.equal(50);

        // 因为周期1开始时没有已确定的抵押，周期1的分红是提不到的
        const balance = await gwt.balanceOf(signers[1].address);
        await (
            await dividend
                .connect(signers[1])
                .withdrawDividends([1], [await gwt.getAddress()])
        ).wait();

        const afterBalance = await gwt.balanceOf(signers[1].address);
        expect(balance).to.equal(afterBalance);

        // withdraw with error cycle
        await expect(
            dividend
                .connect(signers[1])
                .withdrawDividends([2], [await gwt.getAddress()])
        ).to.be.revertedWith("Cannot claim current or future cycle");

        // withdraw with no stake
        await (
            await dividend
                .connect(signers[3])
                .withdrawDividends([1, 0], [await gwt.getAddress()])
        ).wait();
        const balance2 = await gwt.balanceOf(signers[3].address);
        expect(balance2).to.equal(0);

        // stake and unstake only on current cycle
        {
            await (await dividend.connect(signers[1]).stake(20)).wait();
            expect(await dmc.balanceOf(signers[1].address)).to.equal(30);

            // check stake amount with signer[1]
            expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
            expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(50);
            expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(70);

            await (await dividend.connect(signers[1]).unstake(15)).wait();
            expect(await dmc.balanceOf(signers[1].address)).to.equal(45);

            // check stake amount with signer[1]
            expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
            expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(50);
            expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(55);

            await (await dividend.connect(signers[1]).unstake(5)).wait();
            expect(await dmc.balanceOf(signers[1].address)).to.equal(50);

            expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
            expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(50);
            expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(50);
        }

        {
            // test error stake
            await expect(dividend.connect(signers[1]).stake(0)).to.be.revertedWith(
                "Cannot stake 0 DMC"
            );
        }

        {
            // test error unstake
            await expect(
                dividend.connect(signers[1]).unstake(100)
            ).to.be.revertedWith("Insufficient stake amount");

            await expect(dividend.connect(signers[1]).unstake(0)).to.be.revertedWith(
                "Cannot unstake 0"
            );
        }

        {
            // test stake and unstake with effect prev cycle
            await (await dividend.connect(signers[1]).stake(20)).wait();
            await (await dividend.connect(signers[1]).stake(10)).wait();
            expect(await dmc.balanceOf(signers[1].address)).to.equal(20);

            await (await dividend.connect(signers[1]).unstake(45)).wait();
            expect(await dmc.balanceOf(signers[1].address)).to.equal(65);

            expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
            expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(35);
            expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(35);

            await (await dividend.connect(signers[1]).stake(35)).wait();
            expect(await dmc.balanceOf(signers[1].address)).to.equal(30);
            expect(await dividend.connect(signers[1]).getStakeAmount(0)).to.equal(0);
            expect(await dividend.connect(signers[1]).getStakeAmount(1)).to.equal(35);
            expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(70);
        }
    });

    it("test cycle 3", async () => {
        // 前进到周期3，周期2的分红200 GWT,周期3的分红100 GWT
        mine(2, { interval: 1500 });
        await (await dividend.deposit(100, await gwt.getAddress())).wait();

        // check cycle is 3 now
        expect(await dividend.getCurrentCycleIndex()).to.equal(3);

        // cycle 2， total stake 50 + 35 = 85, singer1 stake 35, should get 200 * 35 / 85 = 82
        // and signer2 stake 50, should get 200 * 50 / 85 = 117.6

        // check full stake amount for signer[1] and signer[2] in cycle 2
        expect(await dividend.connect(signers[1]).getStakeAmount(2 - 1)).to.equal(
            35
        );
        expect(await dividend.connect(signers[2]).getStakeAmount(2 - 1)).to.equal(
            50
        );

        // record the token balance of the contract
        let balance_prev;
        {
            balance_prev = BigInt(
                await dividend.getDepositTokenBalance(gwt.getAddress())
            );
            console.log("balance_prev: ", balance_prev);

            // try update once
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                balance_prev
            );
        }

        // test withdraw dividends with cycle 2 for signer[1]
        expect(
            await dividend
                .connect(signers[1])
                .isDividendWithdrawed(2, await gwt.getAddress())
        ).to.equal(false);
        await (
            await dividend
                .connect(signers[1])
                .withdrawDividends([2], [await gwt.getAddress()])
        ).wait();
        expect(
            await dividend
                .connect(signers[1])
                .isDividendWithdrawed(2, await gwt.getAddress())
        ).to.equal(true);
        expect(await gwt.balanceOf(signers[1].address)).to.equal(82);

        // verify the token balance of the contract after withdraw
        {
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                balance_prev - 82n
            );
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                balance_prev - 82n
            );
        }

        // test withdraw second time with cycle 2 for signer[1], will be reverted
        await expect(
            dividend
                .connect(signers[1])
                .withdrawDividends([2], [await gwt.getAddress()])
        ).to.be.revertedWith("Already claimed");

        await expect(
            dividend
                .connect(signers[1])
                .withdrawDividends(
                    [2],
                    [await gwt.getAddress(), "0x0000000000000000000000000000000000000000"]
                )
        ).to.be.revertedWith("Already claimed");

        // 周期3，signer1先存20， 再提取45 DMC出来, 所以周期3的质押实际上是减少了25， 70-25=45
        expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(70);

        // print total balance of stake token in contract
        const balance = await dmc.balanceOf(await dividend.getAddress());
        console.log("total stake amount of DMC in contract: ", balance);

        // check balance with getTotalStaked with current cycle
        expect(
            await dividend.getTotalStaked(await dividend.getCurrentCycleIndex())
        ).to.equal(balance);
        expect(balance).to.equal(120);

        await (await dividend.connect(signers[1]).stake(20)).wait();

        const balance2 = await dmc.balanceOf(await dividend.getAddress());
        console.log(
            "total stake amount of DMC in contract after stake: ",
            balance2
        );
        expect(
            await dividend.getTotalStaked(await dividend.getCurrentCycleIndex())
        ).to.equal(balance2);
        expect(balance2).to.equal(140);

        await (await dividend.connect(signers[1]).unstake(45)).wait();
        expect(await dividend.connect(signers[1]).getStakeAmount(2)).to.equal(45);

        // test withdraw dividends with cycle 2 for signer[2], witch stake amount is 50 and should get 117
        expect(await dividend.connect(signers[2]).getStakeAmount(1)).to.equal(50);
        expect(await dividend.connect(signers[2]).getStakeAmount(2)).to.equal(50);
        await (await dividend.connect(signers[2]).stake(10)).wait();
        await (await dividend.connect(signers[2]).unstake(9)).wait();
        await (await dividend.connect(signers[2]).unstake(1)).wait();
        expect(await dividend.connect(signers[2]).getStakeAmount(1)).to.equal(50);
        expect(await dividend.connect(signers[2]).getStakeAmount(2)).to.equal(50);

        /*
        await dividend
          .connect(signers[2])
          .withdrawDividends([2], [await gwt.getAddress()]);
        expect(await gwt.balanceOf(signers[2].address)).to.equal(117);
        */
    });

    it("test cycle 4", async () => {
        // 强制结算周期3，进入周期4
        mine(2, { interval: 1000 });
        await (await dividend.tryNewCycle()).wait();

        // check gwt balance of the contract
        // 300 - 82 = 218
        expect(await gwt.balanceOf(await dividend.getAddress())).to.equal(218);

        // 周期三的有效质押：signer1 45, signer2 50
        // 周期三的分红池: 100 GWT
        // 所以signer1应该能提到 100 * 45 / 95 = 47.36， signer2应该能提到 100 * 50 / 95 = 52.63
        console.log(
            "signer1 balance before withdraw: ",
            await gwt.balanceOf(signers[1].address)
        );
        await (
            await dividend
                .connect(signers[1])
                .withdrawDividends([3], [await gwt.getAddress()])
        ).wait();

        // cycle 2 withdraw 82, and cycle 3 withdraw 47, total 129
        expect(await gwt.balanceOf(signers[1].address)).to.equal(129);

        // signer2提取两个周期的分红，应该能提到117+52=169 GWT
        await (
            await dividend
                .connect(signers[2])
                .withdrawDividends([2, 3], [await gwt.getAddress()])
        ).wait();
        expect(await gwt.balanceOf(signers[2].address)).to.equal(169);
    });

    it("test cycle N", async () => {
        const totalDeposit = await dividend.getDepositTokenBalance(
            gwt.getAddress()
        );
        const currentCycle = await dividend.getCurrentCycleIndex();
        console.log(
            "total deposit: ",
            totalDeposit,
            " current cycle: ",
            currentCycle
        );

        const stake1 = await dividend
            .connect(signers[1])
            .getStakeAmount(currentCycle);

        // deposit 1 GWT for 5 cycles
        for (let i = 0; i < 5; i++) {
            mine(2, { interval: 1000 });
            await (await dividend.deposit(1, await gwt.getAddress())).wait();

            // check stake amount with signer[1]
            const currentCycle = await dividend.getCurrentCycleIndex();
            expect(
                await dividend.connect(signers[1]).getStakeAmount(currentCycle)
            ).to.equal(stake1);
            expect(
                await dividend.connect(signers[1]).getStakeAmount(currentCycle - 1n)
            ).to.equal(stake1);
        }

        // check the total deposit amount
        expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
            totalDeposit + 5n
        );

        // get current cycle index
        const cycle = await dividend.getCurrentCycleIndex();
        expect(cycle).to.equal(currentCycle + 5n);

        // get current cycle staked amount for signer[1]
        const stake1_now = await dividend.connect(signers[1]).getStakeAmount(cycle);
        console.log("stake1: ", stake1_now);

        // try unstake extend the limit
        await expect(
            dividend.connect(signers[1]).unstake(stake1_now + 1n)
        ).to.be.revertedWith("Insufficient stake amount");

        // record the token balance of signer[1] of DMC
        const balance1 = await dmc.balanceOf(signers[1].address);
        console.log("DMC balance1 of signer[1]: ", balance1);

        // try unstake all
        await (await dividend.connect(signers[1]).unstake(stake1_now)).wait();

        // check balance is right
        const balance2 = await dmc.balanceOf(signers[1].address);
        console.log("DMC balance2 of signer[1]: ", balance2);
        expect(balance2).to.equal(balance1 + stake1_now);

        {
            // try withdraw dividends for prev cycle with signer[1], but is zero
            const balance = await gwt.balanceOf(signers[1].address);
            await (
                await dividend
                    .connect(signers[1])
                    .withdrawDividends([cycle - 1n], [await gwt.getAddress()])
            ).wait();
            expect(await gwt.balanceOf(signers[1].address)).to.equal(balance);
        }

        // stake again with same amount
        await (await dividend.connect(signers[1]).stake(stake1_now)).wait();

        // check balance of gwt in contract for signer[1]
        const balance3 = await dmc.balanceOf(signers[1].address);
        console.log("DMC balance of signer[1]: ", balance3);
        expect(balance3).to.equal(balance1);

        {
            // to next cycle
            mine(2, { interval: 1000 });

            // deposit 10 GWT to current cycle
            await (await dividend.deposit(10, await gwt.getAddress())).wait();

            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                totalDeposit + 5n + 10n
            );

            // try withdraw dividends for prev cycle with signer[1]
            const balance = await gwt.balanceOf(signers[1].address);
            await (
                await dividend
                    .connect(signers[1])
                    .withdrawDividends([cycle], [await gwt.getAddress()])
            ).wait();
            expect(await gwt.balanceOf(signers[1].address)).to.equal(balance);
        }

        {
            // to next cycle
            mine(2, { interval: 1000 });

            // deposit 10 GWT to current cycle
            await (await dividend.deposit(10, await gwt.getAddress())).wait();

            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                totalDeposit + 5n + 10n + 10n
            );

            // check stake amount for signer[1] with previous cycle
            const cycle = await dividend.getCurrentCycleIndex();
            const stake1 = await dividend
                .connect(signers[1])
                .getStakeAmount(cycle - 1n);

            // get stake amount for signer[2] with prev cycle
            const stake2 = await dividend
                .connect(signers[2])
                .getStakeAmount(cycle - 1n);

            // estimate the dividend amount for signer[1] and signer[2]
            const dividend1 = (10n * stake1) / (stake1 + stake2);
            const dividend2 = (10n * stake2) / (stake1 + stake2);

            // try withdraw dividends for prev cycle with signer[1]

            // first check dividend is not withdrawed
            expect(
                await dividend
                    .connect(signers[1])
                    .isDividendWithdrawed(cycle - 1n, await gwt.getAddress())
            ).to.equal(false);

            const balance = await gwt.balanceOf(signers[1].address);
            await (
                await dividend
                    .connect(signers[1])
                    .withdrawDividends([cycle - 1n], [await gwt.getAddress()])
            ).wait();
            expect(await gwt.balanceOf(signers[1].address)).to.equal(
                balance + dividend1
            );

            expect(
                await dividend
                    .connect(signers[1])
                    .isDividendWithdrawed(cycle - 1n, await gwt.getAddress())
            ).to.equal(true);

            // try withdraw dividends for prev cycle with signer[2]
            expect(
                await dividend
                    .connect(signers[2])
                    .isDividendWithdrawed(cycle - 1n, await gwt.getAddress())
            ).to.equal(false);

            const balance2 = await gwt.balanceOf(signers[2].address);
            await (
                await dividend
                    .connect(signers[2])
                    .withdrawDividends([cycle - 1n], [await gwt.getAddress()])
            ).wait();
            expect(await gwt.balanceOf(signers[2].address)).to.equal(
                balance2 + dividend2
            );

            expect(
                await dividend
                    .connect(signers[2])
                    .isDividendWithdrawed(cycle - 1n, await gwt.getAddress())
            ).to.equal(true);
        }
    });

    it("test transfer external", async () => {
        const current_index = await dividend.getCurrentCycleIndex();
        const current_balance = await dividend.getDepositTokenBalance(await gwt.getAddress());

        mine(2, { interval: 1000 });
        expect(await dividend.getCurrentCycleIndex()).to.equal(current_index);

        {
            // Try update the token balance, balance not change so will not step to next cycle
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index);
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                current_balance
            );
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index);


            // Deposit 90 GWT, will step to next cycle
            await (await dividend.deposit(90, await gwt.getAddress())).wait();
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 1n);

            // Update token balance, balance not changed so will not step to next cycle
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 1n);
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                current_balance + 90n
            );

            mine(2, { interval: 1000 });

            // direct transfer to dividend contract and update token balance, will step to next cycle
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 1n);
            await (await gwt.transfer(await dividend.getAddress(), 10)).wait();
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 1n);

            // Update token balance, balance changed so will step to next cycle
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 2n);
            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                current_balance + 100n
            );

            mine(2, { interval: 1000 });

            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 2n);

            // Update token balance, balance changed so will step to next cycle
            await (await dividend.updateTokenBalance(await gwt.getAddress())).wait();
            expect(await dividend.getCurrentCycleIndex()).to.equal(current_index + 2n);

            expect(await dividend.getDepositTokenBalance(gwt.getAddress())).to.equal(
                current_balance + 100n
            );
        }
    });
});
