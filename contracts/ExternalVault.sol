// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title External ERC‑4626 Vault
 * @author Open‑source example
 * @notice A minimal‑yet‑production‑ready ERC‑4626 implementation that can wrap **any** ERC‑20 asset
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @notice Generic, single‑asset ERC‑4626 vault. Pass the underlying token, name, and symbol at construction.
 */
contract ExternalVault is ERC4626, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Optional performance fee in basis points (1 bp = 0.01 %).
    uint16 public performanceFeeBps;
    address public feeRecipient;
    
    /// @notice The name of the vault token
    string private _name;
    /// @notice The symbol of the vault token
    string private _symbol;

    // ───────────────────────────────────────────────────────────────  constructor ──

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        uint16 feeBps_,
        address feeRecipient_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(owner_) {
        require(feeBps_ <= 1000, "fee too high");      // ≤ 10 %
        performanceFeeBps = feeBps_;
        feeRecipient      = feeRecipient_;
        _name = name_;
        _symbol = symbol_;
    }

    // ──────────────────────────────────────────────────────────  pausable helpers ──

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    modifier whenDepositsAllowed() {
        require(!paused(), "vault paused");
        _;
    }

    // ───────────────────────────────────────────────────  ERC‑4626 overrides  ──

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver)
        public
        override
        whenDepositsAllowed
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address receiver)
        public
        override
        whenDepositsAllowed
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenDepositsAllowed
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        whenDepositsAllowed
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }

    /** @dev Take a performance fee on yield whenever someone calls `harvest()`.
     *       In a real strategy you would pull yield from an external protocol first.
     */
    function harvest() external {
        uint256 currentAssets = totalAssets();
        uint256 expectedAssets = convertToAssets(totalSupply());
        if (currentAssets > expectedAssets && performanceFeeBps > 0) {
            uint256 delta = currentAssets - expectedAssets;
            uint256 feeAssets = (delta * performanceFeeBps) / 10_000;
            if (feeAssets > 0) {
                _deposit(msg.sender, feeRecipient, feeAssets, 0); // internal mint to feeRecipient
            }
        }
    }

    // ───────────────────────────────────────────────────  ERC20 overrides ──

    /// @inheritdoc ERC20
    function name() public view virtual override(ERC20, IERC20Metadata) returns (string memory) {
        return _name;
    }

    /// @inheritdoc ERC20
    function symbol() public view virtual override(ERC20, IERC20Metadata) returns (string memory) {
        return _symbol;
    }

    // ───────────────────────────────────────────────────  View functions ──

    /// @notice Get the total assets in the vault
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Get the maximum amount of assets that can be deposited
    function maxDeposit(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Get the maximum amount of shares that can be minted
    function maxMint(address) public pure override returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Get the maximum amount of assets that can be withdrawn
    function maxWithdraw(address owner) public view override returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /// @notice Get the maximum amount of shares that can be redeemed
    function maxRedeem(address owner) public view override returns (uint256) {
        return balanceOf(owner);
    }
}
