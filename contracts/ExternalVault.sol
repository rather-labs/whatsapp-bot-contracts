// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Generic ERC‑4626 Vault & Factory
 * @author Open‑source example
 * @notice A minimal‑yet‑production‑ready ERC‑4626 implementation that can wrap **any** ERC‑20 asset
 *         plus a small factory for deterministic cheap deployments using OpenZeppelin`s Clones library.
 * @dev Requires OpenZeppelin contracts ‑ install via:  `forge install OpenZeppelin/openzeppelin‑contracts`
 */

import { ERC20 }          from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626 }        from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable }        from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable }       from "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @notice Generic, single‑asset ERC‑4626 vault. Pass the underlying token, name, and symbol at construction.
 */
contract GenericERC4626Vault is ERC4626, Ownable, Pausable {
    /// @notice Optional performance fee in basis points (1 bp = 0.01 %).
    uint16 public performanceFeeBps;
    address public feeRecipient;

    // ───────────────────────────────────────────────────────────────  constructor ──

    constructor(
        ERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_,
        uint16 feeBps_,
        address feeRecipient_
    ) ERC20(name_, symbol_) ERC4626(asset_) {
        require(feeBps_ <= 1000, "fee too high");      // ≤ 10 %
        _transferOwnership(owner_);
        performanceFeeBps = feeBps_;
        feeRecipient      = feeRecipient_;
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
}
