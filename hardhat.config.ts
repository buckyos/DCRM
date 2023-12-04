import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import 'hardhat-abi-exporter';

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            },
            viaIR: true
        }
    },
    abiExporter: {
        runOnCompile: true,
        clear: true,
    },
    networks: {
        x1test: {
            url: "https://testrpc.x1.tech",
            accounts: [
                // add your private keys here
            ]
          }
    }
};

export default config;
