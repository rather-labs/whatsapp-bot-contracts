# Wallet Scripts

This directory contains scripts for creating and retrieving wallets.

## Scripts

### 1. createAccount.ts

Generates a new wallet with a random private key.

**Usage:**
```bash
npx ts-node scripts/createAccount.ts
```

**Features:**
- Generates cryptographically secure private keys
- Displays wallet address and private key
- Shows security warnings and next steps
- Includes creation timestamp

**Output:**
- Wallet address and private key
- Creation timestamp
- Security warnings
- Next steps for funding and usage

### 2. getAccount.ts

Retrieves and displays wallet information from the BASE_PRIVATE_KEY environment variable, including ETH balance and token balance from Base Sepolia or Base mainnet.

**Usage:**
```bash
# Check Base Sepolia (default)
npx ts-node scripts/getAccount.ts

# Check Base mainnet
npx ts-node scripts/getAccount.ts base-mainnet
```

**Features:**
- Reads private key from environment variable
- Displays wallet address
- Supports both Base Sepolia and Base mainnet networks
- Fetches and displays ETH balance from the specified network
- Fetches and displays token balance if token address is provided
- Shows balances in both raw units and formatted amounts
- Simple and clean output
- Error handling for missing environment variables and network issues

**Environment Variables:**
- `BASE_PRIVATE_KEY`: Private key for the wallet
- `BASE_SEPOLIA_TOKEN_ADDRESS`: (Optional) Token contract address for Base Sepolia
- `BASE_MAINNET_TOKEN_ADDRESS`: (Optional) Token contract address for Base mainnet

**Output:**
- Wallet address
- ETH balance in ETH
- Token balance in formatted amounts (if token address provided)
- Network information (Base Sepolia or Base mainnet)
- Error handling for network connectivity issues

## Security Notes

⚠️ **IMPORTANT SECURITY WARNINGS:**
- Keep your private keys secure and never share them
- Store private keys in a safe location
- Consider using hardware wallets for large amounts
- Never commit private keys to version control
- Use environment variables for private key storage

## Example Workflow

1. **Generate a new wallet:**
   ```bash
   npx ts-node scripts/createAccount.ts
   ```

2. **Add private key to .env file:**
   ```env
   BASE_PRIVATE_KEY=your_private_key_here
   ```

3. **Retrieve wallet information:**
   ```bash
   npx ts-node scripts/getAccount.ts
   ```

## File Structure

```
scripts/
├── createAccount.ts    # Generate new wallets
├── getAccount.ts       # Retrieve wallet information
└── README.md          # This documentation
```

## Dependencies

- `viem`: For wallet generation and account management
- `dotenv`: For environment variable management
- `@nomicfoundation/hardhat-toolbox-viem`: For Hardhat integration

## Network Support

Both scripts support:
- **Base Sepolia** (`base-sepolia`): Testnet for Base
- **Base Mainnet** (`base-mainnet`): Mainnet for Base 