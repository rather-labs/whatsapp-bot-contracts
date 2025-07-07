import { buildModule} from '@nomicfoundation/hardhat-ignition/modules';
import { baseSepolia, base, hardhat } from 'viem/chains';
import hre from 'hardhat';

const VaultModule = buildModule('Vault', (m) => {
  const deployer = m.getAccount(0);
 
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
    let tokenAddress: any = undefined;
  if (hre.network.config.chainId === baseSepolia.id) {
    tokenAddress = process.env.BASE_SEPOLIA_TOKEN_ADDRESS ?? '';
  } else if (hre.network.config.chainId === base.id) {
    tokenAddress = process.env.BASE_MAINNET_TOKEN_ADDRESS ?? '';
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

  const externalVault0 = m.contract('ExternalVault', [
    asset,
    name,
    symbol,
    owner,
    feeBps,
    feeRecipient,
  ], { id: 'ExternalVault0' });

  const externalVault1 = m.contract('ExternalVault', [
    asset,
    name,
    symbol,
    owner,
    feeBps,
    feeRecipient,
  ], { id: 'ExternalVault1' });

  const externalVault2 = m.contract('ExternalVault', [
    asset,
    name,
    symbol,
    owner,
    feeBps,
    feeRecipient,
  ], { id: 'ExternalVault2' });

  const externalVaults = [externalVault0, externalVault1, externalVault2];

  const Vault = m.contract('TokenVaultWithRelayer', [deployer, tokenAddress, externalVaults]);
  
  return { Vault };
});
export default VaultModule;
