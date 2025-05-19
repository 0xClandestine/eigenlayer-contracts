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

interface ISlashingWithdrawalRouterTypes {
    /// @notice A struct that represents an escrow for a redistribution.
    /// @param underlyingAmount The amount of underlying tokens that is being redistributed.
    /// @param strategy The strategy that is being redistributed.
    /// @param startBlock The block number at which the escrow will be released, assuming the redistribution is not paused.
    struct RedistributionEscrow {
        uint256[] underlyingAmounts;
        IStrategy[] strategies;
        uint32 startBlock;
    }
}

interface ISlashingWithdrawalRouterEvents is ISlashingWithdrawalRouterTypes {
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

    /// @notice Returns the escrow for a redistribution.
    /// @param operatorSet The operator set whose redistribution is being queried.
    /// @param slashId The slash ID of the redistribution that is being queried.
    function getRedistributionEscrow(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (RedistributionEscrow memory);

    /// @notice Returns the paused status of a redistribution.
    /// @param operatorSet The operator set whose redistribution is being queried.
    /// @param slashId The slash ID of the redistribution that is being queried.
    function isRedistributionPaused(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool);
}
