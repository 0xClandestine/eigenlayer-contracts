// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../interfaces/ISlashingWithdrawalRouter.sol";
import "../interfaces/IAllocationManager.sol";
import "../interfaces/IStrategyManager.sol";

abstract contract SlashingWithdrawalRouterStorage is ISlashingWithdrawalRouter {
    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    /// @notice Role privledged with the ability to pause redistribution.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role privledged with the ability to unpause redistribution.
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

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
    uint256[49] private __gap;
}
