# Smart Wallet Contracts

This directory contains the smart contracts for a WhatsApp bot-integrated smart wallet system that enables users to manage their funds through different risk profiles and authentication levels.

## 🏗️ Architecture Overview

The system consists of a main vault contract that manages user funds through external ERC-4626 compliant vaults, each representing different risk profiles. Users can interact with the system through a WhatsApp bot interface, with transactions being relayed through authorized relayers.

### Key Features
- **Multi-Risk Profile Support**: Low, Medium, and High risk vaults
- **Flexible Authentication**: Configurable authorization levels (0-2)
- **Authorization Thresholds**: Configurable limits for the authorization requirement for different operations
- **Relayer System**: Gasless transactions through authorized relayers
- **EIP-712 Signature variant**: Secure off-chain transaction signing when user transaction signing is not a possibility.
- **User Management**: Registration, deposits, withdrawals, and transfers

## 📁 Contract Files

### Core Contracts

#### `contracts/Vault.sol` - Main Vault Contract
The primary contract (`TokenVaultWithRelayer`) that manages user funds and provides the main functionality:

- **User Management**: Register users with wallet addresses
- **Multi-Vault Operations**: Deposit/withdraw from risk-appropriate vaults
- **Transfer Functions**: Send funds to external addresses or between users
- **Profile Management**: Change risk and authentication profiles
- **Access Control**: Role-based permissions for relayers and admins

**Risk Profiles:**
- `0`: Low risk (default)
- `1`: Medium risk  
- `2`: High risk

**Authentication Profiles:**
- `0`: Every action requires verification
- `1`: Deposits/withdrawals to user wallet don't require verification (default)
- `2`: No action requires verification

#### `contracts/VaultEIP712.sol` - EIP-712 Variant Vault
An variant version of the main vault that implements EIP-712 standard for secure off-chain signature verification. 
To be used when it is preferable that the user's don't submit their own authorizations:

- **Typed Data Signing**: Secure transaction signing using EIP-712
- **Signature Verification**: Validate user authorization through cryptographic signatures
- **Gas Efficiency**: Reduced on-chain verification overhead
- **Smart Contract Compatibility**: Support for both EOA and contract wallets

#### `contracts/ExternalVault.sol` - Risk Profile Vaults
A token implementation of an ERC-4626 compliant vault, for testing porpouses. 

#### `contracts/USDCoin.sol` - Mock USDC Token
A token implementation of USDC for local development and testing:

- **ERC-20 Standard**: Standard token functionality
- **6 Decimal Places**: Matches real USDC precision
- **EIP-712 Permit**: Gasless approvals via signatures
- **Governance Features**: Voting capabilities (ERC-20Votes)
- **Supply Controls**: Maximum supply and minting controls

## 🛠️ Development Setup

### Prerequisites

- Node.js (v18+)
- npm or yarn
- Private key for deployment

### Installation

```bash
# Install dependencies
npm install

# Set up environment variables
cp .env.example .env
# Edit .env with your private key and RPC URLs
```

### Environment Variables

Create a `.env` file with the following variables:

```env
# Required
BASE_PRIVATE_KEY=your_private_key_here

# Optional - RPC URLs (defaults to public endpoints)
BASE_SEPOLIA_RPC_URL=your_sepolia_rpc_url
BASE_MAINNET_RPC_URL=your_mainnet_rpc_url

# Network-specific token addresses (for mainnet/testnet deployments)
BASE_SEPOLIA_TOKEN_ADDRESS=0x...
BASE_MAINNET_TOKEN_ADDRESS=0x...

# External vault addresses (if using existing vaults)
BASE_SEPOLIA_VAULT0=0x...
BASE_SEPOLIA_VAULT1=0x...
BASE_SEPOLIA_VAULT2=0x...
BASE_MAINNET_VAULT0=0x...
BASE_MAINNET_VAULT1=0x...
BASE_MAINNET_VAULT2=0x...
```

## 🚀 Usage

### Compilation

```bash
# Compile all contracts
npm run compile
```

### Local Development

```bash
# Start local Hardhat node
npm run start

# Deploy to local network (in another terminal)
npm run deploy:local
```

### Network Deployment

```bash
# Deploy to Base Sepolia testnet
npm run deploy:sepolia

# Deploy to Base mainnet
npm run deploy:mainnet
```

### Account Management

```bash
# Create a new wallet
npm run account:create

# Check account details on Sepolia
npm run account:get:sepolia

# Check account details on mainnet  
npm run account:get:mainnet
```

## 📂 Directory Structure

```
contracts/
├── contracts/                 # Solidity contracts
│   ├── Vault.sol             # Main vault contract
│   ├── VaultEIP712.sol       # EIP-712 enhanced vault
│   ├── ExternalVault.sol     # Risk profile vault implementation
│   └── USDCoin.sol           # Mock USDC token
├── scripts/                   # Utility scripts
│   ├── createAccount.ts      # Generate new wallets
│   ├── getAccount.ts         # Check wallet balances
│   └── README.md             # Scripts documentation
├── ignition/                  # Hardhat Ignition deployment
│   └── modules/
│       └── Vault.ts          # Deployment configuration
├── hardhat.config.ts         # Hardhat configuration
├── package.json              # Dependencies and scripts
└── README.md                 # This file
```

## 🔧 Configuration

### Hardhat Configuration

The project is configured for:

- **Solidity 0.8.28** with optimizer enabled
- **Base Sepolia** and **Base Mainnet** networks
- **Contract size monitoring** via hardhat-contract-sizer
- **Sourcify verification** for contract verification

### Deployment Configuration

The deployment script (`ignition/modules/Vault.ts`) automatically:

- Deploys mock USDC on local network
- Uses existing token addresses on testnets/mainnet
- Creates three external vaults for different risk profiles
- Configures the main vault with proper permissions

## 🔐 Security Considerations

- **Access Control**: Role-based permissions with admin and relayer roles
- **Reentrancy Protection**: All state-changing functions protected
- **Pausable Operations**: Emergency pause functionality
- **Signature Verification**: EIP-712 standard for secure off-chain authorization
- **Nonce Management**: Prevents replay attacks
- **Authorization Thresholds**: Configurable limits for enhanced security

## 📖 Integration Guide

### For WhatsApp Bot Integration

1. **Deploy Contracts**: Use the deployment scripts for your target network
2. **Configure Relayers**: Add bot wallet addresses as relayers
3. **User Registration**: Register WhatsApp users with their wallet addresses
4. **Transaction Relaying**: Use the relayer role to execute user transactions
5. **Signature Verification**: Implement EIP-712 signing in the bot for secure operations

### For Frontend Integration

1. **Contract ABIs**: Generated ABIs are available in the artifacts directory
2. **Network Configuration**: Use the network configurations from hardhat.config.ts
3. **User Interface**: Implement functions to interact with vault operations
4. **Wallet Integration**: Support both EOA and smart contract wallets

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the contract headers for details.

## 📋 TODOs

### Contract Features
- [ ] **User Wallet Management**: Add function to change user wallet addresses
- [ ] **External Vault Migration**: Add function to change external vaults
  - [ ] Retrieve all assets from old vaults
  - [ ] Resend assets to new vaults  
  - [ ] Generate new permits and eliminate old ones
  - [ ] Incorporate timelocks
- [ ] **Risk Management Functions**: Implement comprehensive risk controls
- [ ] **User/Wallet Pausing**: Add functions to pause specific users and/or wallets from committing new transactions
- [ ] **User Blacklisting**: Add functions to blacklist users 

### Testing & Quality Assurance
- [ ] **Comprehensive Test Suite**: Write extensive unit and integration tests
  - [ ] Test all vault operations (deposit, withdraw, transfer)
  - [ ] Test risk profile changes and validations
  - [ ] Test authorization threshold configurations
  - [ ] Test EIP-712 signature verification
  - [ ] Test edge cases and error conditions
- [ ] **Gas Optimization Analysis**: Profile and optimize gas consumption
- [ ] **Security Audit**: Conduct professional security audit
- [ ] **Fuzz Testing**: Implement property-based testing

### Advanced Features
- [ ] **Multi-Signature Support**: Add multi-sig capabilities for high-value operations
- [ ] **Upgrade Mechanisms**: Implement proxy patterns for contract upgrades
- [ ] **Emergency Recovery**: Add emergency recovery procedures for edge cases
- [ ] **Batch Operations**: Support relayer batched transactions for efficiency

### Integration & Tooling
- [ ] **WhatsApp Bot Integration**: Complete integration documentation and examples
- [ ] **API Documentation**: Generate comprehensive API documentation
- [ ] **Integration Examples**: Provide complete integration examples
- [ ] **Monitoring Dashboard**: Build admin dashboard for vault monitoring
- [ ] **Analytics**: Implement usage analytics and reporting

### DevOps & Infrastructure
- [ ] **CI/CD Pipeline**: Set up automated testing and deployment
- [ ] **Contract Verification**: Automate contract verification on block explorers
- [ ] **Deployment Scripts**: Enhance deployment automation
- [ ] **Environment Management**: Improve environment configuration management
- [ ] **Performance Monitoring**: Add contract performance monitoring

### Documentation & UX
- [ ] **User Guides**: Create end-user documentation
- [ ] **Developer Tutorials**: Write step-by-step integration tutorials


### Performance & Scalability
- [ ] **Gas Token Integration**: Implement gas token support for cost optimization
- [ ] **State Optimization**: Optimize contract state for reduced storage costs
- [ ] **Event Optimization**: Optimize event emissions for better indexing

## 🆘 Support

For questions or issues:

1. Check the [scripts README](scripts/README.md) for account management
2. Review the contract documentation in the source files
3. Ensure environment variables are properly configured
4. Verify network connectivity and RPC endpoints 