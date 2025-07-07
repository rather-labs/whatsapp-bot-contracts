// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

contract TokenVaultWithRelayer is EIP712, AccessControl, ReentrancyGuard, Nonces, Pausable {

    using SafeERC20 for IERC20;

    // Create a new role identifier for the relayer role
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    IERC20 public immutable token;

    // Risk profile:
    // 0: Low
    // 1: Medium
    // 2: High
    uint8 public constant NumberOfRiskProfiles = 3;
    // External vaults must be ERC4626 compliant .
    IERC4626[NumberOfRiskProfiles] public externalVaults; 

    // Auth profile:
    // 0: Every action requires verification
    // 1: Only Transfers outside the vault and changing risk and 
    //   auth profile changing requires verification
    // 2: No action requires verification
    uint8 public constant NumberOfAuthProfiles = 3;

    // Actions:
    // 0: RegisterUser (User, Wallet, Permit) - Uses permit for verification
    // 1: Deposit (User, Amount, Nonce)
    // 2: Withdraw (User, Amount, Nonce)
    // 3: Transfer (UserFrom, UserTo, Amount, Nonce)
    // 4: TransferWithinVault (UserFrom, UserTo, Amount, Nonce)
    // 5: SetRiskProfile (User, RiskProfile, Nonce)
    // 6: SetAuthProfile (User, AuthProfile, Nonce)

    // Hashes for EIP712 verification when needed
    bytes32 public constant DEPOSIT_TYPEHASH = keccak256("Deposit(uint256 user,uint256 assets,uint256 nonce)");
    bytes32 public constant WITHDRAW_TYPEHASH = keccak256("Withdraw(uint256 user,uint256 shares,uint8 riskProfile,uint256 nonce)");
    bytes32 public constant TRANSFER_TYPEHASH = keccak256("Transfer(uint256 userFrom,address userTo,uint256 assets,uint256 nonce)");
    bytes32 public constant TRANSFER_WITHIN_VAULT_TYPEHASH = keccak256("TransferWithinVault(uint256 userFrom,uint256 userTo,uint256 assets,uint256 nonce)");
    bytes32 public constant RISK_PROFILE_TYPEHASH = keccak256("SetRiskProfile(uint256 user,uint8 riskProfile,uint256 nonce)");
    bytes32 public constant AUTH_PROFILE_TYPEHASH = keccak256("SetAuthProfile(uint256 user,uint8 authProfile,uint256 nonce)");


    // User data:
    mapping(uint256 => address) public userAddresses;
    mapping(uint256 => uint256) public userShares;
    mapping(uint256 => uint8) public userRiskProfile;
    mapping(uint256 => uint8) public userAuthProfile;


    event RiskProfileSet(uint256 user, uint8 profile);
    event AuthProfileSet(uint256 user, uint8 profile);
    event UserRegistered(uint256 user, address wallet);
    event Deposit(uint256 user, uint256 assets);
    event Withdraw(uint256 user, address addressTo, uint256 assets);
    event Transfer(uint256 userFrom, address userTo, uint256 assets);
    event TransferWithinVault(uint256 userFrom, uint256 userTo, uint256 assets);


    constructor(
        address initialOwner,
        IERC20 _token,
        IERC4626[NumberOfRiskProfiles] memory _externalVaults
    )  
        payable
        EIP712("TokenVaultWithRelayer", "1") // set domain separator
    {
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(RELAYER_ROLE, initialOwner);
        token = _token;
        externalVaults = _externalVaults;
        for (uint8 i = 0; i < NumberOfRiskProfiles; i++) { // Allow all vaults to manage assets from this vault
            _token.forceApprove(address(_externalVaults[i]), type(uint256).max);
        }
    }

    function RegisterUser(
        uint256 _user, 
        address _wallet, 
        uint256 _permitValue,
        uint256 _permitDeadline,
        uint256 _permitNonce,
        bytes calldata _permitSignature
    ) 
        external 
        onlyRole(RELAYER_ROLE) 
        nonReentrant 
    {   
        require(_verifyPermit(_wallet, _permitValue, _permitDeadline, _permitNonce, _permitSignature), "Invalid permit");

        if (userAddresses[_user] != address(0)) {
            revert("User already registered");
        }
        userAddresses[_user] = _wallet;
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

    function withdraw(
        uint256 user,
        address addressTo,
        uint256 assets,
        uint256 nonce,
        bytes calldata signature
    ) external 
      whenNotPaused
      nonReentrant 
    {
        require(userAddresses[user] != address(0), "User not registered");
        require(nonce == nonces(userAddresses[user]), "Invalid nonce");
        if (userAuthProfile[user] < 2) {
            require(_verifyWithdraw(user, addressTo, assets, nonce, signature), "Invalid signature");
        }
        
        _useNonce(userAddresses[user]);

        require(userShares[user] >= externalVaults[userRiskProfile[user]].convertToShares(assets), "Not enough shares");

        uint256 shares = externalVaults[userRiskProfile[user]].withdraw(assets, addressTo, address(this));
        userShares[user] -= shares;

        emit Withdraw(user, addressTo, assets);
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
        if (userAuthProfile[userFrom] < 1) {
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

        if (userAuthProfile[_user] < 2) {
            if (!_verifyRiskProfile(_user, _riskProfile, nonce, signature)) {
                revert("User not authenticated");
            }
        }

        if (userShares[_user] > 0) {
            uint256 assets = externalVaults[userRiskProfile[_user]].withdraw(userShares[_user], address(this), address(this));
            uint256 shares = externalVaults[_riskProfile].deposit(assets, address(this));
            userShares[_user] = shares;
        }
        userRiskProfile[_user] = _riskProfile;
    }

    function ChangeAuthProfile(uint256 _user, uint8 _authProfile, uint256 nonce, bytes calldata signature) 
        external 
        onlyRole(RELAYER_ROLE) 
        nonReentrant  
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require (_authProfile < NumberOfAuthProfiles, "Invalid auth profile");

        if (userAuthProfile[_user] < 2) {
            if (!_verifyAuthProfile(_user, _authProfile, nonce, signature)) {
                revert("User not authenticated");
            }
        }
        userAuthProfile[_user] = _authProfile;
    }

    // --- Off-chain helpers ---
    function getNonce(uint256 user) external view returns (uint256) {
        require(userAddresses[user] != address(0), "User not registered");
        return nonces(userAddresses[user]);
    }

    function getUserAssets(uint256 user) external view returns (uint256) {
        require(userAddresses[user] != address(0), "User not registered");
        return externalVaults[userRiskProfile[user]].convertToAssets(userShares[user]);
    }

    // --- EIP712 Verification ---
    function _verifyDeposit(uint256 user, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(DEPOSIT_TYPEHASH, user, assets, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature) == userAddresses[user];
    }

    function _verifyWithdraw(uint256 user, address addressTo, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(WITHDRAW_TYPEHASH, user, addressTo, assets, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature) == userAddresses[user];
    }

    function _verifyTransfer(uint256 userFrom, address userTo, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, userFrom, userTo, assets, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature) == userAddresses[userFrom];
    }

    function _verifyTransferWithinVault(uint256 userFrom, uint256 userTo, uint256 assets, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(TRANSFER_WITHIN_VAULT_TYPEHASH, userFrom, userTo, assets, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature) == userAddresses[userFrom];
    }

    function _verifyRiskProfile(uint256 user, uint8 riskProfile, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(RISK_PROFILE_TYPEHASH, user, riskProfile, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature) == userAddresses[user];
    }

    function _verifyAuthProfile(uint256 user, uint8 authProfile, uint256 nonce, bytes calldata signature) internal view returns (bool) {
        bytes32 structHash = keccak256(abi.encode(AUTH_PROFILE_TYPEHASH, user, authProfile, nonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        return ECDSA.recover(digest, signature) == userAddresses[user];
    }

    function _verifyPermit(
        address wallet,
        uint256 permitValue,
        uint256 permitDeadline,
        uint256 permitNonce,
        bytes calldata permitSignature
    ) internal view returns (bool) {
        // Verify the permit is for this vault contract
        require(permitValue == uint256(uint160(address(this))), "Invalid permit value");
        require(permitDeadline >= block.timestamp, "Permit expired");
        
        // Cast token to IERC20Permit to access DOMAIN_SEPARATOR
        IERC20Permit permitToken = IERC20Permit(address(token));
        
        // Verify the permit signature using EIP-712
        bytes32 permitHash = keccak256(abi.encodePacked(
            "\x19\x01",
            permitToken.DOMAIN_SEPARATOR(),
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                wallet,
                address(this),
                permitValue,
                permitNonce,
                permitDeadline
            ))
        ));
        
        // Split the signature into v, r, s components
        require(permitSignature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            // Copy calldata to memory for processing
            calldatacopy(0, permitSignature.offset, 65)
            r := mload(0)
            s := mload(32)
            v := byte(0, mload(64))
        }
        
        // Handle signature malleability
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return false;
        
        address signer = ecrecover(permitHash, v, r, s);
        return signer == wallet;
    }

    // --- Admin ---
    function addRelayer(address account) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant 
    {
        grantRole(RELAYER_ROLE, account);
    }

    function changeOwner(address newOwner) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        nonReentrant  
    {
        grantRole(DEFAULT_ADMIN_ROLE, newOwner);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {_pause();}

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {_unpause();}

    // TODO: Add function to change user wallet
    // TODO: Add function to change external vaults. 
    //      - Must retrieve all assets and resend them to the new vaults
    //      - Must generate new permits and eliminate old ones
    // TODO: Add risk management functions
}
