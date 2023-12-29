import hre from "hardhat";
import { expect } from "chai";
import { TestList } from "../typechain-types";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

// 40 datas
const testDatas = [
    { hash: "0xfe9ebc29e44d7ecf31ef37b66dc4116f497e272c842b07e42f88e8a56ebc3f19", score: 886 },
    { hash: "0x2fcb2138412a142e612018a3c254fb7e624b514be54ea30e32beffc0a9f9d0e9", score: 60 },
    { hash: "0x6bfe619d7f2e909fdff715140f3e32e147e42277d942db9a63bf42c5560cff4d", score: 100 },
    { hash: "0x225773598f06d0fb28bbbda320c8265bf0addf9abcb332b09e9cd216223ce10c", score: 856 },
    { hash: "0xad18f0489f29cff75b7d0a2ed0e8655dbb16aedd7e6341359405688068f28e86", score: 648 },
    { hash: "0x62a9e09df440e2aab1727ac172f12da750503207e47d671ca2aab8cda5195e7a", score: 872 },
    { hash: "0x95eecba68d650c7a9fe1fd91413df49b70bff9ffa7ac290d17acccff32e73ce8", score: 918 },
    { hash: "0xbd4a97723001af3b64feca812b251806c44efd2b654433e2e888a5db5f199c79", score: 328 },
    { hash: "0x908bb18ac1694569c1295277745dd711b7ea8b5dddd94cdb84da4e85de37a875", score: 980 },
    { hash: "0x4b712a5e494a513a85bb8d4ce4a0cba327db0607e9cf1f6a555c3eead4faff7a", score: 12 },
    { hash: "0xb76a7ef466b493e89f5d3b9030b49e64fed622f0c03b9966b07d8c13c43ea6bd", score: 493 },
    { hash: "0x1794cb609d11981a582027270d7cdc706e2333003a98d08268a902b8ffe3c4de", score: 78 },
    { hash: "0x739794091c4a0597c6d16c17dbc502c34409a58eeaed5cbcab636f0b5ee68a56", score: 117 },
    { hash: "0xc8f7641bd82f10a93aaecc5be2a78a7d3fbef5931f8a6382787882a449385b85", score: 248 },
    { hash: "0xa8fbebf5b65d2c1f01b62a96e73c5d236891b18b9d2b8d6531dfade5ba172d0c", score: 53 },
    { hash: "0xe3c2b396122bb7461a880d702ab8a3fc91b831fca8d8c459b3fe8dc3eb5fe7b4", score: 551 },
    { hash: "0x865d8518d07f2f1f22781999245638b649b3f907a07e881e23c2634a60a55ea6", score: 193 },
    { hash: "0x4f96b6a711c585faf8d87dd9fe679501de544987536d8f323619dafecb14091e", score: 101 },
    { hash: "0x691e690eff7e4302a4a21fbcf426ae575a45b043c5cdb253673949f7a7c0258c", score: 742 },
    { hash: "0x51d3f2b0909a060163899da6f5e7ade99c7f75180d5e7f48e2d25e1569751fbf", score: 32 },
    { hash: "0x43b13a1e579f5b32682a6a180560c5d461db512d1050cebe6c7b749d6ef4a92e", score: 993 },
    { hash: "0xe4e4e4008386f5b64bc2c1ab67c739958d526779c8a23f5d45c8a40f3c075780", score: 473 },
    { hash: "0x2af0a17870fbabe50e9547d903bc211189bcf42b622cfd144b1727807c29579a", score: 713 },
    { hash: "0xd2149878d9ecececafc9223da0b462f5ba2d3fbeac0333f5af7b1dfa599eeb53", score: 289 },
    { hash: "0x83cf46e8f27e1e1e7fd26e8de462cc78dcddf740f89f09098e6ab6f7b7bc0ce0", score: 803 },
    { hash: "0x2ad262848be7f704e39500e2391f59ded7187ea06cb33e8b4fb688337fa49aca", score: 105 },
    { hash: "0x4afd08325b5df0e050c638646e2b7d21306a95ada2108683760245cf5c248041", score: 450 },
    { hash: "0x4f1a2c28deacfe51e88d49353a3efc1c47f658f3b068dc1ba41527c3b1a5ed8b", score: 684 },
    { hash: "0x83511493d0129f86502b069de47aa2423efb87ae36df2c9819614aaa0eca68aa", score: 605 },
    { hash: "0xb553276e229d38af7437dd202c43618c2f53f938c641386f31f2bad2e5c7d09f", score: 583 },
    { hash: "0x73745b252474cfa53b03e03d6a5ddd2d28ff72c8fec92905aab05b51881039b5", score: 32 },
    { hash: "0x21812335323d8ad1bb718ddf58f0c6d5ef92b2c93cea6b7b016bfbaa13d4d1e5", score: 523 },
    { hash: "0xbe094d46c587179cf4aa299bb5518998cf2bde8ecb69ef4c5914852ad9a81914", score: 926 },
    { hash: "0x4807d1978c5a2a3931c858f268858c7aa36c5122598fad44dcd8164504a32323", score: 922 },
    { hash: "0xae04f31dd67bf1cba36619aa843ec015d05cd73bd1e7ce2ae6e3d748b446636d", score: 299 },
    { hash: "0xfda641d3db8ea3a2e80f961848b150898278404f8611da95b0b60311d59b44ca", score: 674 },
    { hash: "0x9b59d5f3e5a431cb64473fb39bda615388d207a1e9616f79cbd2789554734e6b", score: 879 },
    { hash: "0xad38e0a2ee4f9bc7c09bac6b8dca1a88e547a2a2d02c1a402e78527b66f14cc8", score: 811 },
    { hash: "0x38a3ac792eb72725ce64a0f15e684f53b0ea4c5c8b10b503b22ba103fb7f138d", score: 388 },
    { hash: "0x52213f3dbd5d122daf5ede2f7fe12c7a4b9c283b1a70a3dbab1b242e578737e0", score: 947 },
];

const sortdatas = testDatas.toSorted((a: any, b: any) => {
    if (a.score < b.score) { return 1; } else if (a.score > b.score) { return -1; } else { return 0; }
});

const realMaxLength = 32;

describe("SortedList", function () {
    let contract: TestList;
    async function deployContracts() { 
        let listLibrary = await (await hre.ethers.getContractFactory("SortedScoreList")).deploy();
        contract = await (await hre.ethers.deployContract("TestList", { libraries: { SortedScoreList: await listLibrary.getAddress() } })).waitForDeployment(); 
    }

    before(async () => { 
        await loadFixture(deployContracts)
        // await deployContracts();
    });

    it("set max len", async () => { 
        await (await contract.setMaxLen(8)).wait(); 
        expect(await contract.maxLen()).to.equal(8); 
    })

    it("set max len again will revert", async () => { 
        await expect(contract.setMaxLen(4)).to.be.revertedWith("max_length must be greater than current max_length"); 
    });

    it("set max len greater will be accepted", async () => { 
        await (await contract.setMaxLen(realMaxLength)).wait();
        expect(await contract.maxLen()).to.equal(realMaxLength); 
    })

    it("one element", async () => {
        await (await contract.addScore(testDatas[0].hash, testDatas[0].score)).wait();
        expect(await contract.getLength()).to.equal(1);
        expect(await contract.getRanking(testDatas[0].hash)).to.equal(1);
    })

    it("update first element", async() => {
        //let hash = "0x43b13a1e579f5b32682a6a180560c5d461db512d1050cebe6c7b749d6ef4a92e"

        await (await contract.addScore(testDatas[0].hash, testDatas[0].score+1));

        expect(await contract.getRanking(testDatas[0].hash)).to.equal(1);
    })

    it("two elements", async () => {
        await loadFixture(deployContracts)  // 重置链上数据
        await (await contract.setMaxLen(realMaxLength)).wait();

        await (await contract.addScore(testDatas[1].hash, testDatas[0].score)).wait();
        await (await contract.addScore(testDatas[0].hash, testDatas[0].score)).wait();
        expect(await contract.getLength()).to.equal(2);
        expect(await contract.getRanking(testDatas[1].hash)).to.equal(1);
        expect(await contract.getRanking(testDatas[0].hash)).to.equal(2);
    })

    it("add all elements", async () => {// 这里准备了40个数据，插入之后排序最后一位的数据会被删除
        await loadFixture(deployContracts)  // 重置链上数据
        await (await contract.setMaxLen(realMaxLength)).wait();

        for (let index = 0; index < testDatas.length; index++) {    
            await (await contract.addScore(testDatas[index].hash, testDatas[index].score)).wait();
        }
        expect(await contract.getLength()).to.equal(realMaxLength);
        // 检查顺序
        for (let index = 0; index < realMaxLength; index++) {    
            expect(await contract.getRanking(sortdatas[index].hash)).to.equal(index+1);
        }
    })

    it("update one element", async () => {// 选择原来12位的数据，更新分数为814，超过原来11位的811，12就变成11了，之前的11就变成12了
        let hash = "0x83cf46e8f27e1e1e7fd26e8de462cc78dcddf740f89f09098e6ab6f7b7bc0ce0";
        await (await contract.addScore(hash, 814))
        expect(await contract.getLength()).to.equal(realMaxLength);
        expect(await contract.getRanking(hash)).to.equal(11);
        expect(await contract.getRanking("0xad38e0a2ee4f9bc7c09bac6b8dca1a88e547a2a2d02c1a402e78527b66f14cc8")).to.equal(12);
    })
});