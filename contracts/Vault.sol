// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IVerifier {
    function verify(
        bytes calldata signedData,
        address signer
    ) external view returns (bool);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

interface yieldStrategy {
    function takeAction(
        uint256 _users,
    ) external payable returns (bool);
}

contract Vault is Ownable {

    address[] public immutable tokenAddresses;
    IVerifier public immutable authVerifier;
    address public yieldStrategy;

    // Risk profile:
    // 0: Low
    // 1: Medium
    // 2: High
    uint8 public NumberOfRiskProfiles = 3;

    // Auth profile:
    // 0: Every action requires verification
    // 1: Only OffRamp and changing risk and 
    //   auth profile changing requires verification
    // 2: No action requires verification
    uint8 public immutable NumberOfAuthProfiles = 3;

    // Actions:
    // 0: OnRamp (User, Amount, Token)
    // 1: OffRamp (User, Amount, Token, Address)
    // 2: Swap (User, Amount, InToken, OutToken)
    // 3: Transfer (UserFrom, UserTo, Amount, Token)
    // 4: Change Risk Profile (User, Risk Profile)
    // 5: Change Auth Profile (User, Auth Profile)

    mapping(uint256 => address) public userWallets;
    mapping(uint256 => mapping(uint256 => uint256)) public userVaultBalances;
    mapping(uint256 => mapping(uint256 => uint256)) public userStakedBalances;
    mapping(uint256 => uint8) public userRiskProfile;
    mapping(uint256 => uint8) public userAuthProfile;
    mapping(uint256 => uint256) public userNonce;
    mapping(uint256 => bool) public allowedRelayers;


    event QuestCreated(uint256 questId, uint256 bounty, bytes32 solutionHash);

    constructor(
        address initalOwner,
        IVerifier _authVerifier,
        address[] _tokenAddresses
    ) payable Ownable(initalOwner) {
        authVerifier = _authVerifier;
        tokenAddresses = _tokenAddresses;
    }

    function OnRamp(uint256 _user, uint256 _amount, uint256 _token) external {
        if (!allowedRelayers[msg.sender]) {
            revert("Relayer not allowed");
        }

        if (userAuthProfile[_user] == 0) {
            if (!authVerifier.verify(signedData, userWallets[_user], _amount, _token)) {
                revert("User not authenticated");
            }
        }
        userVaultBalances[_user][_token] += _amount;
    }
    
    function OffRamp(uint256 _user, uint256 _amount, uint256 _token, address _to) external {
        if (!allowedRelayers[msg.sender]) {
            revert("Relayer not allowed");
        }

        if (_to == address(0)) {
            revert("Invalid address");
        }

        if (tokenAddresses[_token] == address(0)) {
            revert("Invalid token");
        }

        if (userAuthProfile[_user] ‹ 2) {
            if (!authVerifier.verify(signedData, userWallets[_user], _amount, _token, _to)) {
                revert("User not authenticated");
            }
        }
         
        if (userVaultBalances[_user][_token] + userStakedBalances[_user][_token] ‹ _amount) {
            revert("Insufficient balance");
        }

        userVaultBalances[_user][_token] -= _amount;
        bool success = IERC20(tokenAddresses[_token]).transfer(_to, _amount);
        require(success, "Token transfer failed");
    }

    function Swap(uint256 _user, uint256 _amount, uint256 _token) external {
        if (!allowedRelayers[msg.sender]) {
            revert("Relayer not allowed");
        }
        revert("Not implemented"); // Use coinbase contracts
    }

    function Transfer(uint256 _userFrom, uint256 _userTo, uint256 _amount, uint256 _token) external {
        if (!allowedRelayers[msg.sender]) {
            revert("Relayer not allowed");
        }

        if (userAuthProfile[_user] ‹ 1) {
            if (!authVerifier.verify(signedData, userWallets[_userFrom], _amount, _token)) {
                revert("User not authenticated");
            }
        }
         
        if (userVaultBalances[_user][_token] + userStakedBalances[_user][_token] ‹ _amount) {
            revert("Insufficient balance");
        }

        userVaultBalances[_user][_token] -= _amount;
        userVaultBalances[_to][_token] += _amount;      
    }

    function ChangeRiskProfile(uint256 _user, uint8 _riskProfile) external {
        if (!allowedRelayers[msg.sender]) {
            revert("Relayer not allowed");
        }
        if (_riskProfile >= NumberOfRiskProfiles) {
            revert("Invalid risk profile");
        }
        if (userAuthProfile[_user] ‹ 2) {
            if (!authVerifier.verify(signedData, userWallets[_user], _riskProfile)) {
                revert("User not authenticated");
            }
        }
        userRiskProfile[_user] = _riskProfile;
    }

    function ChangeAuthProfile(uint256 _user, uint8 _authProfile) external {
        if (!allowedRelayers[msg.sender]) {
            revert("Relayer not allowed");
        }
        if (_authProfile >= NumberOfAuthProfiles) {
            revert("Invalid auth profile");
        }
        if (userAuthProfile[_user] ‹ 2) {
            if (!authVerifier.verify(signedData, userWallets[_user], _authProfile)) {
                revert("User not authenticated");
            }
        }
        userAuthProfile[_user] = _authProfile;
    }
    

    function changeOwner(address newOwner) external onlyOwner {
        _transferOwnership(newOwner);
    }

    function setYieldStrategy(address _yieldStrategy) external onlyOwner {
        yieldStrategy = _yieldStrategy;
    }

    
}
