import type { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox-viem';
import 'hardhat-contract-sizer';
import { baseSepolia, base } from 'viem/chains';

import * as dotenv from 'dotenv';
dotenv.config();

const BASE_SEPOLIA_RPC_URL = process.env.BASE_SEPOLIA_RPC_URL;
const BASE_SEPOLIA_PRIVATE_KEY = process.env.BASE_SEPOLIA_PRIVATE_KEY;


if (!BASE_SEPOLIA_RPC_URL) {
  throw new Error('⛔ Missing environment variable: BASE_SEPOLIA_RPC_URL');
}

if (!BASE_SEPOLIA_PRIVATE_KEY) {
  throw new Error('⛔ Missing environment variable: BASE_SEPOLIA_PRIVATE_KEY');
}


const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: {
        enabled: true,
        runs: 500,
      },
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
  networks: {
    localhost: {
      allowUnlimitedContractSize: false,
      chainId: 31_337,
    },
    baseSepolia: {
      url: baseSepolia.rpcUrls.default.http[0],
      chainId: baseSepolia.id,
      accounts: [BASE_SEPOLIA_PRIVATE_KEY],
      allowUnlimitedContractSize: false,
    },
    base: {
      url: base.rpcUrls.default.http[0],
      chainId: base.id,
      accounts: [BASE_SEPOLIA_PRIVATE_KEY],
      allowUnlimitedContractSize: false,
    },
  },
};

export default config;
