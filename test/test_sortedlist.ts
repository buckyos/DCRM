import hre from "hardhat";
import { expect } from "chai";
import { TestList } from "../typechain-types";

const testDatas = [
    { "hash": "0x39c767e230f1cc4d8fa7baa4ef8c39bc2e4add8680d09bfe086e1efdaa0d6437", "score": 290 }, // 10
    { "hash": "0x96aa737f656f90a2f6f90a293b404f2a44529add34f863a18bf51d47bbaec589", "score": 332 }, // 9
    { "hash": "0xde0f510c9a18f7f15d24f9364e93d1e07a98d5a845fc6f230643a9da89b79ac4", "score": 100 }, // 14
    { "hash": "0x02663478495af95f645416a042fedb2d7237b41c50f6fc5471d7a1235e558f52", "score": 785 }, // 3
    { "hash": "0x7008a25999df0f489a692c3f3c4ccb4aaa45c6867ca2fb417b8b9930ab619dfd", "score": 471 }, // 8
    { "hash": "0xa8889b6afd0e4de49140777bf0b8da7910e5361e463c9f990b36d0770b3f8eae", "score": 474 }, // 7
    { "hash": "0x79218525b0548862f03172bc3c88ad7988b47aab05e1c54febab059e4d33efd4", "score": 88 },  // 15
    { "hash": "0x742797a513cef1dfd466b3decd632284fccc6e1cfcb07d78ad33406a642cb408", "score": 244 }, // 12
    { "hash": "0xd0b648691c90f1d35c814664b32dad56e442eeb58f8d93aafb2cd9f0d346d89e", "score": 679 }, // 6
    { "hash": "0xaa1dc0f0587b2a302e0cd6136026b56ff418f77a9803b87b6e16f28f216193fe", "score": 78 },  // 17
    { "hash": "0xd3fff898a835a8c4702885d65e1ce5394648b26b6b6d044eef0ea998f41b428d", "score": 226 }, // 13
    { "hash": "0xb217112856caa6e5c1dbce3414e4ecb3b4380231208d07601635127bd44ce213", "score": 251 }, // 11
    { "hash": "0x2df33298245c73618a534a77babfdb6aba2cbe447a96cb1e57e53a4af570d86a", "score": 83 },  // 16
    { "hash": "0x257d8456e82b21525dd866ab75dd0fb86b9b2f2e1cec0df6295cd486374fbea3", "score": 691 }, // 5
    { "hash": "0x974319f60fafd6cdbf5dcb6e0b58f64df96e43c4d02198d5393e2e3e5549a531", "score": 782 }, // 4
    { "hash": "0x2568f5563305e91f72b8e7b340178834d1aa9aac63b52dfa13e687a4f5f51646", "score": 840 }, // 2
    { "hash": "0x79e0685a902fe9e705e19acbd80ae3910381dacded27f7a24556566df1335c21", "score": 910 }] // 1

const sortdatas = testDatas.toSorted((a: any, b: any) => {
    if (a.score < b.score) {
        return 1;
    } else if (a.score > b.score) {
        return -1;
    } else {
        return 0;
    }
})

describe("ShortedList", function () {
    let contract: TestList;
    async function deployContracts() {
        let listLibrary = await (await hre.ethers.getContractFactory("SortedScoreList")).deploy();
        contract = await (await hre.ethers.deployContract("TestList", {libraries: {
            SortedScoreList: await listLibrary.getAddress()
        }})).waitForDeployment();
    }

    before(async () => {
        await deployContracts()
    });

    it("set max len", async () => {
        await (await contract.setMaxLen(8)).wait();
        expect(await contract.maxLen()).to.equal(8);
    })

    it("set max len again will revert", async () => {
        await expect(contract.setMaxLen(4)).to.be.revertedWith("max_length must be greater than current max_length");
    });

    it("set max len greater will be accepted", async () => {
        await (await contract.setMaxLen(16)).wait();
        expect(await contract.maxLen()).to.equal(16);
    })

    it("one element", async () => {
        await (await contract.addScore(testDatas[0].hash, testDatas[0].score)).wait();

        expect(await contract.getLength()).to.equal(1);

        expect(await contract.getRanking(testDatas[0].hash)).to.equal(1);
    })

    it("add all elements", async () => {
        // 这里准备了17个数据，插入之后排序最后一位的数据会被删除
        for (let index = 0; index < testDatas.length; index++) {
            await (await contract.addScore(testDatas[index].hash, testDatas[index].score)).wait();
        }

        expect(await contract.getLength()).to.equal(16);

        // 检查顺序
        for (let index = 0; index < sortdatas.length - 1; index++) {
            expect(await contract.getRanking(sortdatas[index].hash)).to.equal(index+1);
        }
    })

    it("update one element", async () => {
        // 选择原来12位的数据，更新分数为254，超过原来11位的251，12就变成11了，之前的11就变成12了
        let hash = "0x742797a513cef1dfd466b3decd632284fccc6e1cfcb07d78ad33406a642cb408";
        await (await contract.addScore(hash, 254))

        expect(await contract.getLength()).to.equal(16);

        expect(await contract.getRanking(hash)).to.equal(11);

        expect(await contract.getRanking("0xb217112856caa6e5c1dbce3414e4ecb3b4380231208d07601635127bd44ce213")).to.equal(12);
    })
});