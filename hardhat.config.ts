import type { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox-viem';
import 'hardhat-contract-sizer';

import * as dotenv from 'dotenv';
dotenv.config();

const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const SEPOLIA_PRIVATE_KEY = process.env.SEPOLIA_PRIVATE_KEY;

if (!SEPOLIA_RPC_URL) {
  throw new Error('⛔ Missing environment variable: SEPOLIA_RPC_URL');
}
if (!ETHERSCAN_API_KEY) {
  throw new Error('⛔ Missing environment variable: ETHERSCAN_API_KEY');
}
if (!SEPOLIA_PRIVATE_KEY) {
  throw new Error('⛔ Missing environment variable: SEPOLIA_PRIVATE_KEY');
}

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
      evmVersion: 'cancun',
      viaIR: false,
    },
  },
  contractSizer: {
    alphaSort: true,
    runOnCompile: true,
    disambiguatePaths: false,
  },
  sourcify: {
    enabled: true,
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API_KEY,
    },
  },
  networks: {
    localhost: {
      allowUnlimitedContractSize: true,
      chainId: 31_337,
    },
    sepolia: {
      url: SEPOLIA_RPC_URL,
      chainId: 11_155_111,
      accounts: [SEPOLIA_PRIVATE_KEY],
      allowUnlimitedContractSize: false,
    },
  },
};

export default config;
