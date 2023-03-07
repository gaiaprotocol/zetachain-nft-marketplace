import "dotenv/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-solhint";
import "hardhat-tracer";

import { HardhatUserConfig } from "hardhat/types";

let accounts;
if (process.env.PRIVATE_KEY) {
    accounts = [process.env.PRIVATE_KEY || "0x0000000000000000000000000000000000000000000000000000000000000000"];
} else {
    accounts = {
        mnemonic: process.env.MNEMONIC || "test test test test test test test test test test test junk",
    };
}

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.17",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        mainnet: {
            url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts,
            chainId: 1,
        },
        polygon: {
            url: `https://polygon-mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts,
            chainId: 137,
        },
        klaytn: {
            url: "https://public-en-cypress.klaytn.net",
            accounts,
            chainId: 8217,
            gasPrice: 250000000000,
        },
        mumbai: {
            url: `https://polygon-mumbai.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts,
            chainId: 80001,
        },
        baobab: {
            url: "https://public-node-api.klaytnapi.com/v1/baobab",
            accounts,
            chainId: 1001,
        },
        popcateum: {
            url: "https://dataseed.popcateum.org",
            accounts,
            chainId: 1213,
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS === "true",
    },
};

export default config;
