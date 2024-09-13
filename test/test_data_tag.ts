import { ethers, upgrades } from "hardhat"
import { DataTag } from "../typechain-types"
import { expect } from "chai"
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

let DATA_HASH = "0x8000000000004640f98243c692fba84742845ca34ba0a92a9438e33319abcd7f";

describe("data tag", function () {
    let data_tag: DataTag
    let tag_hashs: any = {};
    let signers: HardhatEthersSigner[];
    before(async () => {
        data_tag = await ethers.deployContract("DataTag");
        tag_hashs["A"] = await data_tag.calcTagHash(["A"]);
        tag_hashs["B"] = await data_tag.calcTagHash(["A", "B"]);
        tag_hashs["C"] = await data_tag.calcTagHash(["A", "B", "C"]);
        tag_hashs["D"] = await data_tag.calcTagHash(["A", "D"]);

        signers = await ethers.getSigners();
    })

    it("set tag meta", async () => {
        // 测试错误的空路径
        await expect(data_tag.setTagMeta(["A", ""], "meta")).to.be.revertedWith("empty name");

        // 创建路径/A/B/C
        let tx = data_tag.setTagMeta(["A", "B", "C"], "meta_A_B_C");

        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["A"], signers[0].address);
        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["B"], signers[0].address);
        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["C"], signers[0].address);

        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["A"], signers[0].address, signers[0].address, 1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["B"], signers[0].address, signers[0].address, 1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["C"], signers[0].address, signers[0].address, 1);

        expect(await data_tag.getTagInfo(tag_hashs["A"])).to.deep.equal(["/A", ethers.ZeroHash, ["B"]]);

        // 创建路径/A/D
        tx = data_tag.setTagMeta(["A", "D"], "meta_A_D");
        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["D"], signers[0].address);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["D"], signers[0].address, signers[0].address, 1);

        expect(await data_tag.getTagInfo(tag_hashs["A"])).to.deep.equal(["/A", ethers.ZeroHash, ["B", "D"]]);

        // 由于不能检查是否没有某个特定事件，这里用事件个数来检查
        expect((await(await tx).wait())?.logs.length).to.equal(2);

        // 用另一个账户创建路径/A/B/C
        tx = data_tag.connect(signers[1]).setTagMeta(["A", "B", "C"], "meta_A_B_C_1");

        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["A"], signers[1].address);
        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["B"], signers[1].address);
        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["C"], signers[1].address);

        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["A"], signers[1].address, signers[1].address, 1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["B"], signers[1].address, signers[1].address, 1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["C"], signers[1].address, signers[1].address, 1);
    })

    it("check tag meta", async() => {
        // 检查tag信息
        expect(await data_tag.getTagInfo(tag_hashs["A"])).to.deep.equal(["/A", ethers.ZeroHash, ["B", "D"]]);
        expect(await data_tag.getTagInfo(tag_hashs["B"])).to.deep.equal(["/A/B", tag_hashs["A"], ["C"]]);
        expect(await data_tag.getTagInfo(tag_hashs["C"])).to.deep.equal(["/A/B/C", tag_hashs["B"], []]);
        expect(await data_tag.getTagInfo(tag_hashs["D"])).to.deep.equal(["/A/D", tag_hashs["A"], []]);

        // 检查meta
        expect(await data_tag.getTagMeta(tag_hashs["A"], signers[0].address)).to.deep.equal(["", 1, 0, 1]);
        expect(await data_tag.getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C", 1, 0, 1]);
        expect(await data_tag.getTagMeta(tag_hashs["D"], signers[0].address)).to.deep.equal(["meta_A_D", 1, 0, 1]);

        // 用另一个账户检查meta
        expect(await data_tag.connect(signers[1]).getTagMeta(tag_hashs["D"], signers[0].address)).to.deep.equal(["meta_A_D", 1, 0, 0]);
        expect(await data_tag.connect(signers[1]).getTagMeta(tag_hashs["C"], signers[1].address)).to.deep.equal(["meta_A_B_C_1", 1, 0, 1]);
    })

    it("change tag meta", async() => {
        let tx = data_tag.setTagMeta(["A", "B", "C"], "meta_A_B_C1");
        await expect(tx).to.emit(data_tag, "TagUpdated").withArgs(tag_hashs["C"], signers[0].address);
        expect((await(await tx).wait())?.logs.length).to.equal(1);

        expect(await data_tag.getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C1", 1, 0, 1]);
    })

    it("rate tag meta", async() => {
        // signer1反对signer0的tagC
        let tx = data_tag.connect(signers[1]).rateTagMeta(tag_hashs["C"], signers[0], -1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["C"], signers[0].address, signers[1].address, -1);

        expect(await data_tag.connect(signers[1]).getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C1", 1, 1, -1]);

        // signer2支持signer0的tagC
        tx = data_tag.connect(signers[2]).rateTagMeta(tag_hashs["C"], signers[0], 1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["C"], signers[0].address, signers[2].address, 1);
        expect(await data_tag.connect(signers[2]).getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C1", 2, 1, 1]);

        expect(await data_tag.connect(signers[3]).getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C1", 2, 1, 0]);

        // signer1重新赞同对signer0的tagC
        tx = data_tag.connect(signers[1]).rateTagMeta(tag_hashs["C"], signers[0], 1);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["C"], signers[0].address, signers[1].address, 1);
        expect(await data_tag.connect(signers[1]).getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C1", 3, 0, 1]);

        // signer1取消对signer0的tagC的评价
        tx = data_tag.connect(signers[1]).rateTagMeta(tag_hashs["C"], signers[0], 0);
        await expect(tx).to.emit(data_tag, "RateTagMeta").withArgs(tag_hashs["C"], signers[0].address, signers[1].address, 0);
        expect(await data_tag.connect(signers[1]).getTagMeta(tag_hashs["C"], signers[0].address)).to.deep.equal(["meta_A_B_C1", 2, 0, 0]);
    })

    it("add data tag", async () => {
        let tx = data_tag.addDataTag(DATA_HASH, [tag_hashs["D"]], ["signer0 add tag D"]);
        await expect(tx).to.emit(data_tag, "ReplaceDataTag").withArgs(DATA_HASH, ethers.ZeroHash, tag_hashs["D"]);
        await expect(tx).to.emit(data_tag, "RateDataTag").withArgs(DATA_HASH, tag_hashs["D"], signers[0].address, 1);

        tx = data_tag.connect(signers[1]).addDataTag(DATA_HASH, [tag_hashs["C"]], ["signer1 add tag C"]);
        await expect(tx).to.emit(data_tag, "ReplaceDataTag").withArgs(DATA_HASH, ethers.ZeroHash, tag_hashs["C"]);
        await expect(tx).to.emit(data_tag, "RateDataTag").withArgs(DATA_HASH, tag_hashs["C"], signers[1].address, 1);
    })

    it("check data tag", async () => {
        expect(await data_tag.getDataTags(DATA_HASH)).to.deep.equal([tag_hashs["D"], tag_hashs["C"]]);
        expect(await data_tag.connect(signers[1]).getDataTagMeta(DATA_HASH, tag_hashs["C"])).to.deep.equal(["signer1 add tag C", 1, 0, 1]);
        expect(await data_tag.getDataTagMeta(DATA_HASH, tag_hashs["D"])).to.deep.equal(["signer0 add tag D", 1, 0, 1]);
    })
})