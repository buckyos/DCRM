本项目采用hardhat开发框架

## 配置开发测试环境
本项目的hardhat配置文件(hardhat.config.ts)中，已有X1开发网的配置，待X1正式网上线后，项目也将更新X1正式网的配置

### 使用X1开发网进行开发测试
需要准备好X1开发网使用的地址，并通过水龙头(https://www.okx.com/cn/x1/faucet)，给账户准备足够的OKB  
将该地址的私钥，配置在hardhat.config.js的networks.x1test.accounts字段即可。

### 使用X1正式网进行开发测试
需准备X1正式网的地址。部署，测试需前确保账户中有足够的OKB余额  
将该地址的私钥，配置在hardhat.config.js的networks.x1.accounts字段即可。


以下所有的部署和测试命令，都可以使用`--network {network_name}`参数，指定运行的环境：
- 不使用`--network`参数，默认在hardhat本地节点上执行操作
- 使用`--network x1test`参数，在X1开发网上执行操作
- 使用`--network x1`参数，在X1正式网上执行操作。目前该参数不可用
## 部署合约

### 确定部署参数
修改`scripts/deploy.ts`的代码，确保部署参数正确

### 执行部署
配置完成后，在根目录运行`npx hardhat run scripts/deploy.ts --network {network_name}`，即可将所有合约按顺序部署到对应网络上。`{network_name}`指定要部署的网络
等待部署完成后，控制台输出以下两行日志，展示合约的部署地址：
```
PST deployed to: {PST Token Contract Address}
Exchange deployed to: {StorageExchange Contract Address}
```
## 运行测试
### 准备测试账户和测试币
- hardhat本地节点
    无需准备账户和测试币
- X1开发网
    需要准备N(N >= 3)个测试账户和必要的测试币，这3个测试账户分别为：
    1. 合约部署者，供应商的CEO角色, PST Token的默认持有者
    2. 供应商的CFO角色，PST Token测试的默认接收者
    3. 买单的用户角色

    将这些账户的私钥，配置在hardhat.config.js的networks.x1test.accounts字段

### 执行测试用例
在根目录下运行`npx hardhat test`命令，即可在hardhat本地节点上，执行test目录下的所有测试用例。使用`--network x1test`参数，指定在X1开发网上执行部署和测试用例

也可运行`npx hardhat test {test_file}`，单独执行某个指定的测试用例文件