// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "../interfaces/ISlashingWithdrawalRouter.sol";
import "../interfaces/IAllocationManager.sol";
import "../interfaces/IStrategyManager.sol";
import "../interfaces/IStrategy.sol";

abstract contract SlashingWithdrawalRouterStorage is ISlashingWithdrawalRouter {
    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @notice The pause status for the `burnOrRedistributeShares` function.
    /// @dev Allows all burn or redistribution outflows to be temporarily halted.
    uint8 public constant PAUSED_BURN_OR_REDISTRIBUTE_SHARES = 0;

    /// -----------------------------------------------------------------------
    /// Immutable Storage
    /// -----------------------------------------------------------------------

    /// @notice Returns the EigenLayer `AllocationManager` address.
    IAllocationManager public immutable allocationManager;

    /// @notice Returns the EigenLayer `StrategyManager` address.
    IStrategyManager public immutable strategyManager;

    /// -----------------------------------------------------------------------
    /// Mutable Storage
    /// -----------------------------------------------------------------------

    /// @notice Returns the escrow for a given operator set and slash ID.
    mapping(bytes32 operatorSetKey => mapping(uint256 slashId => RedistributionEscrow escrow)) internal _escrow;

    /// @notice Returns the paused status for a given operator set and slash ID.
    mapping(bytes32 operatorSetKey => mapping(uint256 slashId => bool paused)) internal _paused;

    /// -----------------------------------------------------------------------
    /// Construction
    /// -----------------------------------------------------------------------

    constructor(IAllocationManager _allocationManager, IStrategyManager _strategyManager) {
        allocationManager = _allocationManager;
        strategyManager = _strategyManager;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[48] private __gap;
}
