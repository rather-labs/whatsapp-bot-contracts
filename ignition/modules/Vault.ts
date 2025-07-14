import { buildModule} from '@nomicfoundation/hardhat-ignition/modules';
import { baseSepolia, base, hardhat } from 'viem/chains';
import hre from 'hardhat';

const VaultModule = buildModule('Vault', (m) => {
  const deployer = m.getAccount(0);
 
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
  let tokenAddress: any = undefined;
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
  let externalVault0: any = undefined;
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
  let externalVault1: any = undefined;
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
  let externalVault2: any = undefined;
  if (hre.network.config.chainId === baseSepolia.id) {
    tokenAddress = process.env.BASE_SEPOLIA_TOKEN_ADDRESS ?? '';
    externalVault0 = process.env.BASE_SEPOLIA_VAULT0 ;
    externalVault1 = process.env.BASE_SEPOLIA_VAULT1 ;
    externalVault2 = process.env.BASE_SEPOLIA_VAULT2 ;
  } else if (hre.network.config.chainId === base.id) {
    tokenAddress = process.env.BASE_MAINNET_TOKEN_ADDRESS ?? '';
    externalVault0 = process.env.BASE_MAINNET_VAULT0 ?? '';
    externalVault1 = process.env.BASE_MAINNET_VAULT1 ?? '';
    externalVault2 = process.env.BASE_MAINNET_VAULT2 ?? '';
  } else if (hre.network.config.chainId !== hardhat.id) {
    throw new Error("Invalid network");
  }
  if (!tokenAddress && hre.network.config.chainId !== hardhat.id) {
    throw new Error("token address environment variable must be set for the current network");
  }

  if (hre.network.config.chainId === hardhat.id) {
    tokenAddress = m.contract('USDCoin', [deployer]);
  }

  // Define constructor parameters for ExternalVault
  const asset = tokenAddress;
  const name = "USD Coin";
  const symbol = "USDC";
  const owner = deployer;
  const feeBps = 100; // 1% fee
  const feeRecipient = deployer;

  if (!externalVault0) {
    externalVault0 = m.contract('ExternalVault', [
      asset,
      name,
      symbol,
      owner,
      feeBps,
      feeRecipient,
    ], { id: 'ExternalVault0' });
  }
  if (!externalVault1) {
    externalVault1 = m.contract('ExternalVault', [
      asset,
      name,
      symbol,
      owner,
      feeBps,
      feeRecipient,
    ], { id: 'ExternalVault1' });
  }
  if (!externalVault2) {
    externalVault2 = m.contract('ExternalVault', [
      asset,
      name,
      symbol,
      owner,
      feeBps,
      feeRecipient,
    ], { id: 'ExternalVault2' });
  }

  const externalVaults = [externalVault0, externalVault1, externalVault2];

  const Vault = m.contract('TokenVaultWithRelayer', [deployer, tokenAddress, externalVaults]);
  
  return { Vault };
});
export default VaultModule;
