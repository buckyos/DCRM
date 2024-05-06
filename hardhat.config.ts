import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import 'hardhat-abi-exporter';
import "hardhat-gas-reporter";
import '@openzeppelin/hardhat-upgrades';
import "@nomicfoundation/hardhat-verify";

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,

        }
    },
    abiExporter: {
        runOnCompile: true,
        clear: true,
    },
    gasReporter: {
        enabled: false,
    },
    networks: {
        ethereum: {
            url: "",
            accounts: [
                
            ]
        },
        xtest: {
            url: "https://testrpc.xlayer.tech",
            accounts: [
                // add your private keys here
            ]
        },
        xlayer: {
            url: "https://rpc.xlayer.tech"
        },
        hardhat: {
            mining: {
                auto: true,
                interval: 15000,
            }
        },
        localhost: {
            gas: "auto"
        }
    },
    sourcify: {
        enabled: true
    },
    mocha: {
        bail: true,
        timeout: 24*60*60*1000
    }
};

export default config;
