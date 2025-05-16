// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import "../permissions/Pausable.sol";
import "../mixins/SemVerMixin.sol";
import "./SlashingWithdrawalRouterStorage.sol";

contract SlashingWithdrawalRouter is
    Initializable,
    SlashingWithdrawalRouterStorage,
    AccessControlUpgradeable,
    Pausable,
    SemVerMixin
{
    using SafeERC20 for IERC20;
    using OperatorSetLib for OperatorSet;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    /// @dev Checks whether a caller is the `StrategyManager`.
    modifier onlyStrategyManager() {
        _checkOnlyStrategyManager();
        _;
    }

    /// @dev Checks whether a caller is the `StrategyManager`, throws `UnauthorizedCaller` if not.
    function _checkOnlyStrategyManager() internal view virtual {
        require(msg.sender == address(strategyManager), OnlyStrategyManager());
    }

    /// -----------------------------------------------------------------------
    /// Initialization
    /// -----------------------------------------------------------------------

    constructor(
        IAllocationManager _allocationManager,
        IStrategyManager _strategyManager,
        IPauserRegistry _pauserRegistry,
        string memory _version
    )
        SlashingWithdrawalRouterStorage(_allocationManager, _strategyManager)
        Pausable(_pauserRegistry)
        SemVerMixin(_version)
    {
        _disableInitializers();
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function initialize(
        uint256 initialPausedStatus
    ) external initializer {
        _setPausedStatus(initialPausedStatus);
    }

    /// -----------------------------------------------------------------------
    /// Actions
    /// -----------------------------------------------------------------------

    /// @inheritdoc ISlashingWithdrawalRouter
    function startBurnOrRedistributeShares(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IERC20[] calldata tokens,
        uint256[] calldata underlyingAmounts
    ) external onlyStrategyManager {
        // Create a storage pointer to the escrow array.
        RedistributionEscrow[] storage escrow = _escrow[operatorSet.key()][slashId];

        // Assert that the input arrays are of the same length.
        require(tokens.length == underlyingAmounts.length, InputArrayLengthMismatch());

        // Start a redistribution for each strategy that was slashed.
        for (uint256 i = 0; i < tokens.length; i++) {
            // Assert that the token is not the zero address for sanity.
            require(tokens[i] != IERC20(address(0)), InputAddressZero());

            // Store the escrowed redistribution.
            escrow.push(
                RedistributionEscrow({
                    underlyingAmount: underlyingAmounts[i],
                    token: tokens[i],
                    startBlock: uint32(block.number)
                })
            );

            // Emit the event.
            emit RedistributionInitiated(operatorSet, slashId, tokens[i], underlyingAmounts[i], uint32(block.number));
        }
    }

    // TODO: Only releaser can call this.

    /// @inheritdoc ISlashingWithdrawalRouter
    function burnOrRedistributeShares(OperatorSet calldata operatorSet, uint256 slashId) external {
        // Fetch the redistribution recipient for the operator set from the AllocationManager.
        address redistributionRecipient = allocationManager.getRedistributionRecipient(operatorSet);

        // Create a storage pointer to the escrow array.
        RedistributionEscrow[] storage escrow = _escrow[operatorSet.key()][slashId];

        // Fetch the length of the escrow array.
        uint256 n = escrow.length;

        // Assert that the escrow is not paused.
        require(!_paused[operatorSet.key()][slashId], RedistributionCurrentlyPaused());

        // Iterate over the escrow array in reverse order and pop the processed entries from storage.
        for (uint256 i = n; i > 0; i--) {
            uint256 index = i - 1;

            // TODO: Add configurable delay on a strategy-by-strategy basis for each operator set within ALM and update 3.5 day constant.

            if (block.number > escrow[index].startBlock + (3.5 days / 12 seconds)) {
                // Emit the event.
                emit RedistributionReleased(
                    operatorSet, slashId, escrow[index].token, escrow[index].underlyingAmount, redistributionRecipient
                );

                // Transfer the escrowed tokens to the caller.
                escrow[index].token.safeTransfer(redistributionRecipient, escrow[index].underlyingAmount);

                // Remove the processed entry.
                escrow.pop();
            }
        }
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function pauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external onlyPauser {
        bool paused = _paused[operatorSet.key()][slashId];

        // Assert that the redistribution is not already paused.
        require(!paused, RedistributionCurrentlyPaused());

        // Set the paused flag to true.
        _paused[operatorSet.key()][slashId] = true;

        // Emit the event.
        emit RedistributionPaused(operatorSet, slashId);
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function unpauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external onlyUnpauser {
        bool paused = _paused[operatorSet.key()][slashId];

        // Assert that the redistribution is already paused.
        require(paused, RedistributionNotPaused());

        // Set the paused flag to false.
        _paused[operatorSet.key()][slashId] = false;

        // Emit the event.
        emit RedistributionUnpaused(operatorSet, slashId);
    }
}
