import { generatePrivateKey, privateKeyToAccount } from 'viem/accounts';

interface WalletInfo {
  privateKey: string;
  address: string;
  mnemonic?: string;
  createdAt: string;
}


function generateWallet(): WalletInfo {

  // Generate a random private key
  const privateKey = generatePrivateKey();
  
  // Derive the account from the private key
  const account = privateKeyToAccount(privateKey);
  
  const walletInfo: WalletInfo = {
    privateKey: privateKey,
    address: account.address,
    createdAt: new Date().toISOString(),
  };
  
  return walletInfo;
}

function displayWalletInfo(walletInfo: WalletInfo): void {
  
  console.log('\n=== Generated Wallet ===');
  console.log(`Address: ${walletInfo.address}`);
  console.log(`Private Key: ${walletInfo.privateKey}`);
  console.log(`Created: ${walletInfo.createdAt}`);
  console.log('========================\n');
  
  console.log('⚠️  SECURITY WARNING ⚠️');
  console.log('Keep your private key secure and never share it!');
  console.log('Store it in a safe location and consider using a hardware wallet for large amounts.\n');
  
  console.log('📋 Next Steps:');
  console.log('1. Add this private key to your .env file as BASE_SEPOLIA_PRIVATE_KEY or BASE_MAINNET_PRIVATE_KEY');
  console.log("2. Fund this address with some ETH for gas fees");
  console.log('3. Use this wallet with the setUpAccount.ts script\n');
}

function main() {
  try { 
    console.log("Generating new wallet...\n");
    
    // Generate wallet
    const wallet = generateWallet();
    
    // Display wallet information
    displayWalletInfo(wallet);
    
    console.log('✅ Wallet generated successfully!');
    
  } catch (error) {
    console.error('❌ Error generating wallet:', error);
    process.exit(1);
  }
}

// Export functions for use in other scripts
export { generateWallet, displayWalletInfo };

// Run the script if called directly
if (require.main === module) {
  main();
}
