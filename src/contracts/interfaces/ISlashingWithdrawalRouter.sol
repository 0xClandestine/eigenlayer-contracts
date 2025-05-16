// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/OperatorSetLib.sol";

interface ISlashingWithdrawalRouterErrors {
    /// @notice Thrown when a null address is provided as an input.
    error InputAddressZero();

    /// @notice Thrown when a redistribution already exists.
    error RedistributionAlreadyExists();

    /// @notice Thrown when a caller does not have the necessary role to perform an action.
    error UnauthorizedCaller();

    /// @notice Thrown when a redistribution is already paused.
    error RedistributionCurrentlyPaused();

    /// @notice Thrown when a redistribution is not paused.
    error RedistributionNotPaused();

    /// @notice Thrown when a redistribution is not mature.
    error RedistributionNotMature();
}

interface ISlashingWithdrawalRouterTypes {
    /// @notice A struct that represents an escrow for a redistribution.
    /// @param amount The amount of tokens that is being redistributed.
    /// @param token The token that is being redistributed.
    /// @param maturity The block number at which the escrow will be released, assuming the redistribution is not paused.
    /// @param paused Whether the redistribution is paused.
    struct RedistributionEscrow {
        uint256 amount;
        IERC20 token;
        uint32 maturity;
        bool paused;
    }
}

interface ISlashingWithdrawalRouterEvents is ISlashingWithdrawalRouterTypes {
    /// @notice Emitted when a redistribution is initiated.
    event RedistributionInitiated(
        OperatorSet operatorSet, uint256 slashId, IERC20 token, uint256 amount, uint32 maturity
    );

    /// @notice Emitted when a redistribution is released.
    event RedistributionReleased(
        OperatorSet operatorSet, uint256 slashId, IERC20 token, uint256 amount, address recipient
    );

    /// @notice Emitted when a redistribution is paused.
    event RedistributionPaused(OperatorSet operatorSet, uint256 slashId);

    /// @notice Emitted when a redistribution is unpaused.
    event RedistributionUnpaused(OperatorSet operatorSet, uint256 slashId);
}

interface ISlashingWithdrawalRouter is ISlashingWithdrawalRouterErrors, ISlashingWithdrawalRouterEvents {
    /// @notice Initializes initial admin, pauser, and unpauser roles.
    /// @param initialAdmin The address of the initial admin.
    /// @param initialPauser The address of the initial pauser.
    /// @param initialUnpauser The address of the initial unpauser.
    function initialize(address initialAdmin, address initialPauser, address initialUnpauser) external;

    /// @notice Locks up a redistribution.
    /// @param operatorSet The operator set whose redistribution is being locked up.
    /// @param slashId The slash ID of the redistribution that is being locked up.
    /// @param token The token that is being redistributed.
    /// @param amount The amount of tokens that is being redistributed.
    /// @param maturity The block number at which the escrow will be released, assuming the redistribution is not paused.
    function startBurnOrRedistributeShares(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IERC20 token,
        uint256 amount,
        uint32 maturity
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
}
