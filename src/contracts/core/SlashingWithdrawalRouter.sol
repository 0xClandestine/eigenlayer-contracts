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
        IStrategy[] calldata strategies,
        uint256[] calldata underlyingAmounts
    ) external onlyStrategyManager {
        // Assert that the input arrays are of the same length.
        require(strategies.length == underlyingAmounts.length, InputArrayLengthMismatch());

        // Create a storage pointer to the escrow array.
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Start a redistribution for each strategy that was slashed.
        for (uint256 i = 0; i < strategies.length; ++i) {
            // Assert that the strategy is not the zero address for sanity.
            require(address(strategies[i]) != address(0), InputAddressZero());

            // Emit the event.
            emit RedistributionInitiated(
                operatorSet, slashId, strategies[i], underlyingAmounts[i], uint32(block.number)
            );
        }

        escrow.underlyingAmounts = underlyingAmounts;
        escrow.strategies = strategies;
        escrow.startBlock = uint32(block.number);
    }

    // TODO: Only releaser can call this.

    /// @inheritdoc ISlashingWithdrawalRouter
    function burnOrRedistributeShares(OperatorSet calldata operatorSet, uint256 slashId) external {
        // Assert that the escrow is not paused.
        require(!_paused[operatorSet.key()][slashId], RedistributionCurrentlyPaused());

        // Fetch the redistribution recipient for the operator set from the AllocationManager.
        address redistributionRecipient = allocationManager.getRedistributionRecipient(operatorSet);

        // Create a storage pointer to the escrow array.
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Fetch the length of the escrow array.
        uint256 n = escrow.underlyingAmounts.length;

        // Iterate over the escrow array in reverse order and pop the processed entries from storage.
        for (uint256 i = n; i > 0; i--) {
            uint256 index = i - 1;
            uint32 delay; // TODO

            // Skip immature redistributions rather than reverting to avoid denial of service.
            if (block.number > escrow.startBlock + delay) {
                // Emit the event.
                emit RedistributionReleased(
                    operatorSet,
                    slashId,
                    escrow.strategies[index],
                    escrow.underlyingAmounts[index],
                    redistributionRecipient
                );

                // Transfer the escrowed tokens to the caller.
                escrow.strategies[index].underlyingToken().safeTransfer(
                    redistributionRecipient, escrow.underlyingAmounts[index]
                );

                // First swap the current entry with the last element.
                escrow.underlyingAmounts[index] = escrow.underlyingAmounts[escrow.underlyingAmounts.length - 1];
                escrow.strategies[index] = escrow.strategies[escrow.strategies.length - 1];

                // Then pop the last element off the array, since it's now a duplicate.
                escrow.underlyingAmounts.pop();
                escrow.strategies.pop();
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// Emergency Actions
    /// -----------------------------------------------------------------------

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
