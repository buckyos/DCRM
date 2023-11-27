const PSTToken = artifacts.require("PSTToken");

module.exports = function (deployer) {
    deployer.deploy(PSTToken, 1000000000); // 假设初始供应量为1000000
};
