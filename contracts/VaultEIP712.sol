// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

contract TokenVaultWithRelayerEIP712 is EIP712, AccessControl, ReentrancyGuard, Nonces, Pausable {

    bytes4 internal constant MAGIC = 0x1626ba7e;   // ERC-1271 success value

    using SafeERC20 for IERC20;

    // Create a new role identifier for the relayer role
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    IERC20 public immutable token;
    IERC20Permit public immutable tokenPermit;

    // Risk profile:
    // 0: Low (Default)
    // 1: Medium
    // 2: High
    uint8 public constant NumberOfRiskProfiles = 3;
    // External vaults must be ERC4626 compliant .
    IERC4626[NumberOfRiskProfiles] public externalVaults; 

    // Auth profile:
    // 0: Every action requires verification
    // 1: Deposits and withdrawals to user wallet does not require verification (Default)
    // 2: No action requires verification
    uint8 public constant NumberOfAuthProfiles = 3;

    // Actions:
    // 0: RegisterUser (User, Wallet) 
    // 1: Deposit (User, Amount, Nonce)
    // 2: Withdraw (User, Amount, Nonce)
    // 3: Transfer (UserFrom, UserTo, Amount, Nonce)
    // 4: TransferWithinVault (UserFrom, UserTo, Amount, Nonce)
    // 5: ChangeRiskProfile (User, RiskProfile, Nonce)
    // 6: ChangeAuthProfile (User, AuthProfile, Nonce)

    // Hashes for EIP712 verification when needed
    bytes32 public constant DEPOSIT_TYPEHASH = keccak256("Deposit(uint256 user,uint256 assets,uint256 nonce)");
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256("Withdraw(uint256 user,uint256 assets,uint256 nonce)");
    bytes32 public constant TRANSFER_TYPEHASH = keccak256("Transfer(uint256 userFrom,address userTo,uint256 assets,uint256 nonce)");
    bytes32 public constant TRANSFER_WITHIN_VAULT_TYPEHASH = keccak256("TransferWithinVault(uint256 userFrom,uint256 userTo,uint256 assets,uint256 nonce)");
    bytes32 public constant RISK_PROFILE_TYPEHASH = keccak256("ChangeRiskProfile(uint256 user,uint8 riskProfile,uint256 nonce)");
    bytes32 public constant AUTH_PROFILE_TYPEHASH = keccak256("ChangeAuthProfile(uint256 user,uint8 authProfile,uint256 nonce)");


    // User data:
    mapping(uint256 => address) public userAddresses;
    mapping(uint256 => uint256) public userShares;
    mapping(uint256 => uint8) public userRiskProfile;
    mapping(uint256 => uint8) public userAuthProfile;


    event RiskProfileSet(uint256 user, uint8 profile);
    event AuthProfileSet(uint256 user, uint8 profile);
    event UserRegistered(uint256 user, address wallet);
    event Deposit(uint256 user, uint256 assets);
    event Withdraw(uint256 user, uint256 assets);
    event Transfer(uint256 userFrom, address userTo, uint256 assets);
    event TransferWithinVault(uint256 userFrom, uint256 userTo, uint256 assets);
    event RelayerAdded(address account);
    event OwnerChanged(address newOwner);

    constructor(
        address initialOwner,
        address _token,
        IERC4626[NumberOfRiskProfiles] memory _externalVaults
    )  
        payable
        EIP712("TokenVaultWithRelayer", "1") // set domain separator
    {
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(RELAYER_ROLE, initialOwner);
        token = IERC20(_token);
        tokenPermit = IERC20Permit(_token);
        externalVaults = _externalVaults;
        for (uint8 i = 0; i < NumberOfRiskProfiles; i++) { // Allow all vaults to manage assets from this vault
            token.forceApprove(address(_externalVaults[i]), type(uint256).max);
        }
    }

    function RegisterUser(
        uint256 _user, 
        address _wallet
    ) 
        external 
        onlyRole(RELAYER_ROLE) 
        nonReentrant 
    {   
        require(userAddresses[_user] == address(0), "User already registered");
        
        userAddresses[_user] = _wallet;
        userAuthProfile[_user] = 1;

        emit UserRegistered(_user, _wallet);
    }    


    // --- Deposit/withdraw with per-user risk profile ---
    function deposit(
        uint256 user,
        uint256 assets,
        uint256 nonce,
        bytes calldata signature
    ) external 
      whenNotPaused
      nonReentrant 
    {
        require(userAddresses[user] != address(0), "User not registered");
        require(nonce == nonces(userAddresses[user]), "Invalid nonce");
        if (userAuthProfile[user] < 1) {
            require(_verifyDeposit(user, assets, nonce, signature), "Invalid signature");
        } 

        _useNonce(userAddresses[user]);

        // Pull tokens from user and deposit to chosen vault
        token.safeTransferFrom(userAddresses[user], address(this), assets);
        uint256 shares = externalVaults[userRiskProfile[user]].deposit(assets, address(this));
        userShares[user] += shares;

        emit Deposit(user, assets);
    }

    // Withdraw from vault to user wallet
    function withdraw(
        uint256 user,
        uint256 assets,
        uint256 nonce,
        bytes calldata signature
    ) external 
      whenNotPaused
      nonReentrant 
    {
        require(userAddresses[user] != address(0), "User not registered");
        require(nonce == nonces(userAddresses[user]), "Invalid nonce");
        if (userAuthProfile[user] < 1) {
            require(_verifyWithdraw(user, assets, nonce, signature), "Invalid signature");
        }
        
        _useNonce(userAddresses[user]);

        require(userShares[user] >= externalVaults[userRiskProfile[user]].convertToShares(assets), "Not enough shares");

        uint256 shares = externalVaults[userRiskProfile[user]].withdraw(assets, userAddresses[user], address(this));
        userShares[user] -= shares;

        emit Withdraw(user, assets);
    }

    function transfer(
        uint256 userFrom,
        address userTo,
        uint256 assets,
        uint256 nonce,
        bytes calldata signature
    ) external 
        whenNotPaused
        nonReentrant 
    {
        require(userAddresses[userFrom] != address(0), "User not registered");
        require(nonce == nonces(userAddresses[userFrom]), "Invalid nonce");
        if (userAuthProfile[userFrom] < 2) {
            require(_verifyTransfer(userFrom, userTo, assets, nonce, signature), "Invalid signature");
        }
        _useNonce(userAddresses[userFrom]);

        uint256 shares = externalVaults[userRiskProfile[userFrom]].withdraw(assets, userTo, address(this));
        userShares[userFrom] -= shares;

        emit Transfer(userFrom, userTo, assets);
    }

    function transferWithinVault(
        uint256 userFrom,
        uint256 userTo,
        uint256 assets,
        uint256 nonce,
        bytes calldata signature
    ) external 
      whenNotPaused 
      nonReentrant  
    {
        require(userAddresses[userFrom] != address(0), "User not registered");
        require(userAddresses[userTo] != address(0), "Receiver not registered");
        require(nonce == nonces(userAddresses[userFrom]), "Invalid nonce");
        if (userAuthProfile[userFrom] < 2) {
            require(_verifyTransferWithinVault(userFrom, userTo, assets, nonce, signature), "Invalid signature");
        }
        _useNonce(userAddresses[userFrom]);

        uint8 profileFrom = userRiskProfile[userFrom];
        uint8 profileTo = userRiskProfile[userTo];

        if (profileFrom == profileTo) {
            uint256 shares = externalVaults[profileFrom].convertToShares(assets);
            userShares[userFrom] -= shares;
            userShares[userTo] += shares;
        } else {
            uint256 sharesFrom = externalVaults[profileFrom].withdraw(assets, address(this), userAddresses[userTo]);
            uint256 sharesTo = externalVaults[profileTo].deposit(assets, userAddresses[userTo]);
            userShares[userFrom] -= sharesFrom;
            userShares[userTo] += sharesTo;
        }

        emit TransferWithinVault(userFrom, userTo, assets);
    }

    function ChangeRiskProfile(uint256 _user, uint8 _riskProfile, uint256 nonce, bytes calldata signature) 
        external 
        onlyRole(RELAYER_ROLE) 
        nonReentrant  
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require (_riskProfile < NumberOfRiskProfiles, "Invalid risk profile");
        require(nonce == nonces(userAddresses[_user]), "Invalid nonce");

        if (userAuthProfile[_user] < 2) {
            require(_verifyRiskProfile(_user, _riskProfile, nonce, signature), "Invalid signature");
        }

        _useNonce(userAddresses[_user]);

        if (userShares[_user] > 0) {
            uint256 assets = externalVaults[userRiskProfile[_user]].withdraw(userShares[_user], address(this), address(this));
            uint256 shares = externalVaults[_riskProfile].deposit(assets, address(this));
            userShares[_user] = shares;
        }
        userRiskProfile[_user] = _riskProfile;

        emit RiskProfileSet(_user, _riskProfile);
    }

    function ChangeAuthProfile(uint256 _user, uint8 _authProfile, uint256 nonce, bytes calldata signature) 
        external 
        onlyRole(RELAYER_ROLE) 
        nonReentrant  
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require (_authProfile < NumberOfAuthProfiles, "Invalid auth profile");
        require(nonce == nonces(userAddresses[_user]), "Invalid nonce");

        if (userAuthProfile[_user] < 2) {
            require(_verifyAuthProfile(_user, _authProfile, nonce, signature), "Invalid signature");
        }

        _useNonce(userAddresses[_user]);

        userAuthProfile[_user] = _authProfile;

        emit AuthProfileSet(_user, _authProfile);
    }
    
    // --- Off-chain helpers ---
    function getNonce(uint256 user) external view returns (uint256) {
        require(userAddresses[user] != address(0), "User not registered");
        return nonces(userAddresses[user]);
    }

    function getUserWallet(uint256 user) external view returns (address) {
        return userAddresses[user];
    }

    function getUserShares(uint256 user) external view returns (uint256) {
        require(userAddresses[user] != address(0), "User not registered");
        return userShares[user];
    }

    function getUserRiskProfile(uint256 user) external view returns (uint8) {
        require(userAddresses[user] != address(0), "User not registered");
        return userRiskProfile[user];
    }

    function getUserAuthProfile(uint256 user) external view returns (uint8) {
        require(userAddresses[user] != address(0), "User not registered");
        return userAuthProfile[user];
    }

    function getUserAssets(uint256 user) external view returns (uint256) {
        require(userAddresses[user] != address(0), "User not registered");
        return externalVaults[userRiskProfile[user]].convertToAssets(userShares[user]);
    }

    // --- EIP712 Verification ---
    function _verifyDeposit(uint256 user, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(DEPOSIT_TYPEHASH, user, assets, nonce));
        return SignatureChecker.isValidSignatureNow(userAddresses[user], _hashTypedDataV4(structHash), signature);
    }

    function _verifyWithdraw(uint256 user, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(WITHDRAW_TYPEHASH, user, assets, nonce));
        return SignatureChecker.isValidSignatureNow(userAddresses[user], _hashTypedDataV4(structHash), signature);
    }

    function _verifyTransfer(uint256 userFrom, address userTo, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, userFrom, userTo, assets, nonce));
        return SignatureChecker.isValidSignatureNow(userAddresses[userFrom], _hashTypedDataV4(structHash), signature);
    }

    function _verifyTransferWithinVault(uint256 userFrom, uint256 userTo, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(TRANSFER_WITHIN_VAULT_TYPEHASH, userFrom, userTo, assets, nonce));
        return SignatureChecker.isValidSignatureNow(userAddresses[userFrom], _hashTypedDataV4(structHash), signature);
    }

    function _verifyRiskProfile(uint256 user, uint8 riskProfile, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(RISK_PROFILE_TYPEHASH, user, riskProfile, nonce));
        return SignatureChecker.isValidSignatureNow(userAddresses[user], _hashTypedDataV4(structHash), signature);
    }

    function _verifyAuthProfile(uint256 user, uint8 authProfile, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(AUTH_PROFILE_TYPEHASH, user, authProfile, nonce));
        return SignatureChecker.isValidSignatureNow(userAddresses[user], _hashTypedDataV4(structHash), signature);
    }

    // --- Admin ---
    function addRelayer(address account) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        grantRole(RELAYER_ROLE, account);
        emit RelayerAdded(account);
    }

    function changeOwner(address newOwner) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant  
    {
        grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        emit OwnerChanged(newOwner);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {_pause();}

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {_unpause();}

    // TODO: Add function to change user wallet
    // TODO: Add function to change external vaults. 
    //      - Must retrieve all assets and resend them to the new vaults
    //      - Must generate new permits and eliminate old ones
    // TODO: Add risk management functions
    // TODO: Add functions to blacklist users
}
