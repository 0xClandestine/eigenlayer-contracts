// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "../interfaces/IStrategy.sol";
import "../libraries/OperatorSetLib.sol";

interface ISlashingWithdrawalRouterErrors {
    /// @notice Thrown when a caller is not the strategy manager.
    error OnlyStrategyManager();

    /// @notice Thrown when a caller is not the redistribution recipient.
    error OnlyRedistributionRecipient();

    /// @notice Thrown when a redistribution is already paused.
    error RedistributionCurrentlyPaused();

    /// @notice Thrown when a redistribution is not paused.
    error RedistributionNotPaused();

    /// @notice Thrown when a redistribution is not mature.
    error RedistributionNotMature();
}

interface ISlashingWithdrawalRouterEvents {
    /// @notice Emitted when a redistribution is initiated.
    event RedistributionInitiated(
        OperatorSet operatorSet, uint256 slashId, IStrategy strategy, uint256 underlyingAmount, uint32 startBlock
    );

    /// @notice Emitted when a redistribution is released.
    event RedistributionReleased(
        OperatorSet operatorSet, uint256 slashId, IStrategy strategy, uint256 underlyingAmount, address recipient
    );

    /// @notice Emitted when a redistribution is paused.
    event RedistributionPaused(OperatorSet operatorSet, uint256 slashId);

    /// @notice Emitted when a redistribution is unpaused.
    event RedistributionUnpaused(OperatorSet operatorSet, uint256 slashId);
}

interface ISlashingWithdrawalRouter is ISlashingWithdrawalRouterErrors, ISlashingWithdrawalRouterEvents {
    /// @notice Initializes initial admin, pauser, and unpauser roles.
    /// @param initialPausedStatus The initial paused status of the router.
    function initialize(
        uint256 initialPausedStatus
    ) external;

    /// @notice Locks up a redistribution.
    /// @param operatorSet The operator set whose redistribution is being locked up.
    /// @param slashId The slash ID of the redistribution that is being locked up.
    /// @param strategy The strategy that whose underlying tokens are being redistributed.
    /// @param underlyingAmount The amount of underlying tokens that are being redistributed.
    function startBurnOrRedistributeShares(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IStrategy strategy,
        uint256 underlyingAmount
    ) external;

    /// @notice Releases a redistribution.
    /// @param operatorSet The operator set whose redistribution is being released.
    /// @param slashId The slash ID of the redistribution that is being released.
    /// @dev The caller must be the redistribution recipient, unless the redistribution recipient
    /// is the default burn address in which case anyone can call.
    function burnOrRedistributeShares(OperatorSet calldata operatorSet, uint256 slashId) external;

    /// NOTE: Will likely want arrayfied or range-based aliases so we can quickly pause spammed malicious slashes.

    /// @notice Pauses a redistribution.
    /// @param operatorSet The operator set whose redistribution is being paused.
    /// @param slashId The slash ID of the redistribution that is being paused.
    function pauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external;

    /// @notice Unpauses a redistribution.
    /// @param operatorSet The operator set whose redistribution is being unpaused.
    /// @param slashId The slash ID of the redistribution that is being unpaused.
    function unpauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external;

    /// @notice Returns the pending slash IDs for an operator set.
    /// @param operatorSet The operator set whose pending slash IDs are being queried.
    function getPendingSlashIds(
        OperatorSet calldata operatorSet
    ) external view returns (uint256[] memory);

    /// @notice Returns the pending burn or redistributions for an operator set and slash ID.
    /// @param operatorSet The operator set whose pending burn or redistributions are being queried.
    /// @param slashId The slash ID of the burn or redistribution that is being queried.
    /// @return strategies The strategies that are pending burn or redistribution.
    /// @return underlyingAmounts The underlying amounts that are pending burn or redistribution.
    function getPendingBurnOrRedistributions(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (IStrategy[] memory strategies, uint256[] memory underlyingAmounts);

    /// @notice Returns all pending burn or redistributions for an operator set.
    /// @param operatorSet The operator set whose pending burn or redistributions are being queried.
    /// @return strategies The nested list of strategies that are pending burn or redistribution.
    /// @return underlyingAmounts The nested list of underlying amounts that are pending burn or redistribution.
    function getPendingBurnOrRedistributions(
        OperatorSet calldata operatorSet
    ) external view returns (IStrategy[][] memory strategies, uint256[][] memory underlyingAmounts);

    /// @notice Returns the number of pending burn or redistributions for an operator set and slash ID.
    /// @param operatorSet The operator set whose pending burn or redistributions are being queried.
    /// @param slashId The slash ID of the burn or redistribution that is being queried.
    /// @return The number of pending burn or redistributions.
    function getPendingBurnOrRedistributionsCount(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (uint256);

    /// @notice Returns the pending underlying amount for a strategy for an operator set and slash ID.
    /// @param operatorSet The operator set whose pending underlying amount is being queried.
    /// @param slashId The slash ID of the burn or redistribution that is being queried.
    /// @param strategy The strategy whose pending underlying amount is being queried.
    /// @return The pending underlying amount.
    function getPendingUnderlyingAmountForStrategy(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IStrategy strategy
    ) external view returns (uint256);

    /// @notice Returns the paused status of a redistribution.
    /// @param operatorSet The operator set whose redistribution is being queried.
    /// @param slashId The slash ID of the redistribution that is being queried.
    /// @return The paused status of the redistribution.
    function isRedistributionPaused(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool);
}
