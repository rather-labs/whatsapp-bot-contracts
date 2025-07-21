// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

contract TokenVaultWithRelayer is AccessControl, ReentrancyGuard, Nonces, Pausable {

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
    // 0: registerUser (User, Wallet) 
    // 1: deposit (User, Amount, Nonce)
    // 2: withdraw (User, Amount, Nonce)
    // 3: transfer (UserFrom, UserTo, Amount, Nonce)
    // 4: transferWithinVault (UserFrom, UserTo, Amount, Nonce)
    // 5: changeRiskProfile (User, RiskProfile, Nonce)
    // 6: changeAuthProfile (User, AuthProfile, Nonce)
    // 7: changeAuthThreshold (User, AuthThreshold, Nonce)

    // User data:
    mapping(uint256 => address) public userAddresses;
    mapping(uint256 => uint256) public userShares;
    mapping(uint256 => uint8) public userRiskProfile;
    mapping(uint256 => uint8) public userAuthProfile;
    mapping(uint256 => uint256) public userAuthThreshold;


    event RiskProfileSet(uint256 user, uint8 profile);
    event AuthProfileSet(uint256 user, uint8 profile);
    event AuthThresholdSet(uint256 user, uint256 threshold);
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
    {
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(RELAYER_ROLE, initialOwner);
        token = IERC20(_token);
        tokenPermit = IERC20Permit(_token);
        externalVaults = _externalVaults;
    }

    function registerUser(
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
        uint256 _user,
        uint256 _assets,
        uint256 _nonce
    ) external 
      whenNotPaused
      nonReentrant 
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require(_nonce == nonces(userAddresses[_user]), "Invalid nonce");
    
        if (userAuthProfile[_user] < 1 && userAuthThreshold[_user] < _assets) {
            require(userAddresses[_user] == msg.sender, "The user must authorize this action");
        } else { 
            require(hasRole(RELAYER_ROLE, msg.sender) || userAddresses[_user] == msg.sender, 
            "Only authorized relayers or the user can authorize this action"
            );
        }

        _useNonce(userAddresses[_user]);

        // Pull tokens from user and deposit to chosen vault
        token.safeTransferFrom(userAddresses[_user], address(this), _assets);
        uint256 shares = externalVaults[userRiskProfile[_user]].deposit(_assets, address(this));
        userShares[_user] += shares;

        emit Deposit(_user, _assets);
    }

    // Withdraw from vault to user wallet
    function withdraw(
        uint256 _user,
        uint256 _assets,
        uint256 _nonce
    ) external 
      whenNotPaused
      nonReentrant 
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require(_nonce == nonces(userAddresses[_user]), "Invalid nonce");
        if (userAuthProfile[_user] < 1 && userAuthThreshold[_user] < _assets) {
            require(userAddresses[_user] == msg.sender, "The user must authorize this action");
        } else {
            require(hasRole(RELAYER_ROLE, msg.sender) || userAddresses[_user] == msg.sender, 
            "Only authorized relayers or the user can authorize this action"
            );
        }
        
        _useNonce(userAddresses[_user]);

        require(userShares[_user] >= externalVaults[userRiskProfile[_user]].convertToShares(_assets), "Not enough shares");

        uint256 shares = externalVaults[userRiskProfile[_user]].withdraw(_assets, userAddresses[_user], address(this));
        userShares[_user] -= shares;

        emit Withdraw(_user, _assets);
    }

    // Given an ammount to be paid by the user, transforms it to an ammount of shares from the vault and
    //  assets from the wallet if the shares are not enough.
    function getTransferValues(uint256 _user, uint256 _amount) 
        internal view 
        returns (uint256 _assetsFromVault, uint256 _assetsFromWallet) 
    {
        uint256 _totalVaultAssets = externalVaults[userRiskProfile[_user]
            ].convertToAssets(userShares[_user]);
        if (_amount < _totalVaultAssets) {
            return (_amount, 0);
        }
        uint256 _totalWalletAssets = token.balanceOf(userAddresses[_user]);
        require(_totalWalletAssets+_totalVaultAssets >= _amount, "Not enough assets in vault and wallet to transfer");
        return (_totalVaultAssets, _amount - _totalVaultAssets);
    }

    function transfer(
        uint256 _userFrom,
        address _userTo,
        uint256 _assets,
        uint256 _nonce
    ) external 
        whenNotPaused
        nonReentrant 
    {
        require(userAddresses[_userFrom] != address(0), "User not registered");
        require(_nonce == nonces(userAddresses[_userFrom]), "Invalid nonce");
        if (userAuthProfile[_userFrom] < 2 && userAuthThreshold[_userFrom] < _assets) {
            require(userAddresses[_userFrom] == msg.sender, "The user must authorize this action");
        } else {
            require(hasRole(RELAYER_ROLE, msg.sender) || userAddresses[_userFrom] == msg.sender, 
            "Only authorized relayers or the user can authorize this action"
            );
        }
        
        (uint256 _assetsFromVault, uint256 _assetsFromWallet) = getTransferValues(_userFrom, _assets);

        _useNonce(userAddresses[_userFrom]);

        uint256 shares = externalVaults[userRiskProfile[_userFrom]].withdraw(_assetsFromVault, _userTo, address(this));
        userShares[_userFrom] -= shares;
        if (_assetsFromWallet > 0) {
            token.safeTransferFrom(userAddresses[_userFrom], _userTo, _assetsFromWallet);
        }

        emit Transfer(_userFrom, _userTo, _assets);
    }

    function transferWithinVault(
        uint256 _userFrom,
        uint256 _userTo,
        uint256 _assets,
        uint256 _nonce
    ) external 
      whenNotPaused 
      nonReentrant  
    {
        require(userAddresses[_userFrom] != address(0), "User not registered");
        require(_nonce == nonces(userAddresses[_userFrom]), "Invalid nonce");
        if (userAuthProfile[_userFrom] < 2 && userAuthThreshold[_userFrom] < _assets) {
            require(userAddresses[_userFrom] == msg.sender, "The user must authorize this action");
        } else {
            require(hasRole(RELAYER_ROLE, msg.sender) || userAddresses[_userFrom] == msg.sender, 
            "Only authorized relayers or the user can authorize this action"
            );
        }

        uint8 profileFrom = userRiskProfile[_userFrom];
        // If the receiver is not registered, it will put the assets in the low risk vault
        uint8 profileTo = userRiskProfile[_userTo]; 

        (uint256 _assetsFromVault, uint256 _assetsFromWallet) = getTransferValues(_userFrom, _assets);

        _useNonce(userAddresses[_userFrom]);

        if (profileFrom == profileTo) {
            uint256 shares = externalVaults[profileFrom].convertToShares(_assetsFromVault);
            userShares[_userFrom] -= shares;
            userShares[_userTo] += shares;
        } else {
            uint256 sharesFrom = externalVaults[profileFrom].withdraw(
                _assetsFromVault, address(this), address(this)
                );
            uint256 sharesTo = externalVaults[profileTo].deposit(_assetsFromVault, address(this));
            userShares[_userFrom] -= sharesFrom;
            userShares[_userTo] += sharesTo;
        }

        if (_assetsFromWallet > 0) {
            token.safeTransferFrom(userAddresses[_userFrom], address(this), _assetsFromWallet);
            uint256 shares = externalVaults[userRiskProfile[_userTo]].deposit(
                _assetsFromWallet, address(this)
                );
            userShares[_userTo] += shares;
        }

        emit TransferWithinVault(_userFrom, _userTo, _assets);
    }

    function changeRiskProfile(uint256 _user, uint8 _riskProfile, uint256 nonce) 
        external 
        nonReentrant  
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require (_riskProfile < NumberOfRiskProfiles, "Invalid risk profile");
        require(nonce == nonces(userAddresses[_user]), "Invalid nonce");

        if (userAuthProfile[_user] < 2) {
            require(userAddresses[_user] == msg.sender, "The user must authorize this action");
        } else {
            require(hasRole(RELAYER_ROLE, msg.sender) || userAddresses[_user] == msg.sender, 
            "Only authorized relayers or the user can authorize this action"
            );
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

    function changeAuthProfile(uint256 _user, uint8 _authProfile, uint256 nonce) 
        external 
        nonReentrant  
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require (_authProfile < NumberOfAuthProfiles, "Invalid auth profile");
        require(nonce == nonces(userAddresses[_user]), "Invalid nonce");

        if (userAuthProfile[_user] < 2) {
            require(userAddresses[_user] == msg.sender, "The user must authorize this action");
        } else {
            require(hasRole(RELAYER_ROLE, msg.sender) || userAddresses[_user] == msg.sender, 
            "Only authorized relayers or the user can authorize this action"
            );
        }

        _useNonce(userAddresses[_user]);

        userAuthProfile[_user] = _authProfile;

        emit AuthProfileSet(_user, _authProfile);
    }

    function changeAuthThreshold(uint256 _user, uint256 _authThreshold, uint256 nonce) 
        external 
        nonReentrant  
    {
        require(userAddresses[_user] != address(0), "User not registered");
        require(nonce == nonces(userAddresses[_user]), "Invalid nonce");

        require(userAddresses[_user] == msg.sender, "The user must authorize this action");

        _useNonce(userAddresses[_user]);

        userAuthThreshold[_user] = _authThreshold;

        emit AuthThresholdSet(_user, _authThreshold);
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

    function getUserAuthThreshold(uint256 user) external view returns (uint256) {
        require(userAddresses[user] != address(0), "User not registered");
        return userAuthThreshold[user];
    }

    function getUserAssets(uint256 user) external view returns (uint256) {
        return externalVaults[userRiskProfile[user]].convertToAssets(userShares[user]);
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
    // TODO: Add functions to pause specific users and or wallets from commiting new transactions
}
