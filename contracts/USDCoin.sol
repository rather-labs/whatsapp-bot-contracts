// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title USD Coin (USDC)
 * @dev A safe ERC20 token implementation with additional features
 * @notice This is a mock USDC token for testing purposes on local network
 */
contract USDCoin is ERC20, ERC20Permit, ERC20Votes, Ownable, Pausable {
    
    /// @notice Maximum supply of USDC tokens (1 billion with 6 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**6;
    
    /// @notice Decimals for USDC (6 decimals like real USDC)
    uint8 public constant DECIMALS = 6;

    constructor(address initialOwner) 
        ERC20("USD Coin", "USDC") 
        ERC20Permit("USD Coin")
        Ownable(initialOwner)
    {
        // Mint initial supply to the owner
        _mint(initialOwner, MAX_SUPPLY);
    }

    /**
     * Circle’s implementation overrides the EIP-712 version to "2".
     * We do the same ↓ so domainSeparator matches real USDC behaviour.
     */
    function version() public pure virtual returns (string memory) {
        return "2";
    }

    /**
     * @dev Override decimals to return 6 (like real USDC)
     */
    function decimals() public view virtual override returns (uint8) {
        return DECIMALS;
    }

    /**
     * @dev Pause all token transfers
     * @notice Only owner can pause
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause all token transfers
     * @notice Only owner can unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Mint new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @notice Only owner can mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from caller
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Burn tokens from specified address (requires allowance)
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     * @notice Requires allowance from the from address
     */
    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
        whenNotPaused
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
} 