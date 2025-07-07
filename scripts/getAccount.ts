import { privateKeyToAccount } from 'viem/accounts';
import { createWalletClient, http } from 'viem';
import { getBalance, readContract } from 'viem/actions';
import { baseSepolia, base } from 'viem/chains';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// ERC20 ABI for balanceOf function
const ERC20_ABI = [
  {
    "constant": true,
    "inputs": [{"name": "_owner", "type": "address"}],
    "name": "balanceOf",
    "outputs": [{"name": "balance", "type": "uint256"}],
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [],
    "name": "decimals",
    "outputs": [{"name": "", "type": "uint8"}],
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [],
    "name": "symbol",
    "outputs": [{"name": "", "type": "string"}],
    "type": "function"
  }
] as const;

interface NetworkConfig {
  name: string;
  chain: typeof baseSepolia | typeof base;
  rpcUrl: string;
  tokenEnvKey: string;
}

const NETWORKS = {
  'base-sepolia': {
    name: 'Base Sepolia',
    chain: baseSepolia,
    rpcUrl: baseSepolia.rpcUrls.default.http[0],
    tokenEnvKey: 'BASE_SEPOLIA_TOKEN_ADDRESS'
  },
  'base-mainnet': {
    name: 'Base Mainnet',
    chain: base,
    rpcUrl: base.rpcUrls.default.http[0],
    tokenEnvKey: 'BASE_MAINNET_TOKEN_ADDRESS'
  }
} as const;

/**
 * Retrieves wallet account from BASE_PRIVATE_KEY environment variable
 * @returns The wallet account object
 */
export function getAccount() {
  const privateKey = process.env.BASE_PRIVATE_KEY;
  
  if (!privateKey) {
    throw new Error('⛔ Missing environment variable: BASE_PRIVATE_KEY');
  }

  // Remove '0x' prefix if present
  const cleanPrivateKey = privateKey.startsWith('0x') ? privateKey.slice(2) : privateKey;
  
  // Generate account from private key
  const account = privateKeyToAccount(`0x${cleanPrivateKey}`);
  
  return account;
}

/**
 * Creates a wallet client for the specified network
 * @param account - The wallet account object
 * @param network - The network to use ('base-sepolia' or 'base-mainnet')
 * @returns The wallet client
 */
export function createClient(account: ReturnType<typeof privateKeyToAccount>, network = 'base-sepolia') {
  if (!NETWORKS[network as keyof typeof NETWORKS]) {
    throw new Error(`Invalid network: ${network}. Supported networks: ${Object.keys(NETWORKS).join(', ')}`);
  }

  const networkConfig = NETWORKS[network as keyof typeof NETWORKS];
  const client = createWalletClient({
    account,
    chain: networkConfig.chain,
    transport: http(networkConfig.rpcUrl),
  });
  
  return client;
}

/**
 * Fetches balance for a wallet on the specified network
 * @param client - The wallet client
 * @param address - The address to check balance for
 * @returns The balance in wei
 */
export async function fetchBalance(client: ReturnType<typeof createWalletClient>, address: string) {
  try {
    const balance = await getBalance(client, { address: address as `0x${string}` });
    return balance;
  } catch (error) {
    console.error('❌ Error getting balance:', error);
    throw error;
  }
}

/**
 * Fetches token balance for a wallet
 * @param client - The wallet client
 * @param tokenAddress - The token contract address
 * @param walletAddress - The wallet address to check
 * @returns Object containing token balance, decimals, and symbol
 */
export async function fetchTokenBalance(
  client: ReturnType<typeof createWalletClient>, 
  tokenAddress: string, 
  walletAddress: string
) {
  try {
    const [balance, decimals, symbol] = await Promise.all([
      readContract(client, {
        address: tokenAddress as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'balanceOf',
        args: [walletAddress as `0x${string}`]
      }),
      readContract(client, {
        address: tokenAddress as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'decimals'
      }),
      readContract(client, {
        address: tokenAddress as `0x${string}`,
        abi: ERC20_ABI,
        functionName: 'symbol'
      })
    ]);

    return {
      balance: balance as bigint,
      decimals: decimals as number,
      symbol: symbol as string
    };
  } catch (error) {
    console.error('❌ Error getting token balance:', error);
    throw error;
  }
}

/**
 * Displays wallet information including balance and token balance
 * @param account - The wallet account object
 * @param balance - The wallet balance in wei
 * @param tokenInfo - The token balance information
 * @param network - The network name
 */
export function displayAccountInfo(
  account: ReturnType<typeof privateKeyToAccount>, 
  balance?: bigint,
  tokenInfo?: { balance: bigint; decimals: number; symbol: string },
  network?: string
) {
  console.log('\n=== Wallet Account ===');
  console.log('📝 Address:', account.address);
  if (balance !== undefined) {
    console.log('💎 Balance:', (Number(balance) / 1e18).toFixed(6), 'ETH');
  }
  if (tokenInfo) {
    const tokenAmount = Number(tokenInfo.balance) / (10 ** tokenInfo.decimals);
    console.log(`🪙 ${tokenInfo.symbol} Balance:`, tokenAmount.toFixed(6), tokenInfo.symbol);
  }
  console.log('🌐 Network:', network || 'Base Sepolia');
  console.log('========================\n');
}

async function main() {
  try {
    // Get network from command line arguments or default to base-sepolia
    const network = process.argv[2] || 'base-sepolia';
    
    if (!NETWORKS[network as keyof typeof NETWORKS]) {
      console.log('Available networks:');
      for (const net of Object.keys(NETWORKS)) {
        console.log(`  - ${net}: ${NETWORKS[net as keyof typeof NETWORKS].name}`);
      }
      console.log('\nUsage: npx ts-node scripts/getAccount.ts [network]');
      console.log('Example: npx ts-node scripts/getAccount.ts base-mainnet');
      process.exit(1);
    }

    const networkConfig = NETWORKS[network as keyof typeof NETWORKS];
    console.log(`Retrieving wallet account for ${networkConfig.name}...\n`);
    
    // Get account from environment
    const account = getAccount();
    
    // Create client for the specified network
    const client = createClient(account, network);
    
    // Fetch ETH balance
    let balance: bigint | undefined;
    try {
      balance = await fetchBalance(client, account.address);
    } catch (error) {
      console.log('⚠️  Could not fetch ETH balance (network might be down or insufficient funds)');
    }
    
    // Fetch token balance if token address is provided
    let tokenInfo: { balance: bigint; decimals: number; symbol: string } | undefined;
    const tokenAddress = process.env[networkConfig.tokenEnvKey];
    if (tokenAddress) {
      try {
        tokenInfo = await fetchTokenBalance(client, tokenAddress, account.address);
      } catch (error) {
        console.log('⚠️  Could not fetch token balance (token might not exist or network issue)');
      }
    }
    
    // Display account information
    displayAccountInfo(account, balance, tokenInfo, networkConfig.name);
    
    console.log('✅ Account retrieved successfully!');
    
  } catch (error) {
    console.error('❌ Error retrieving account:', error);
    process.exit(1);
  }
}

// Run the script if called directly
if (require.main === module) {
  main();
} 