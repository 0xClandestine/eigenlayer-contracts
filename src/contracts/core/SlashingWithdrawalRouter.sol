// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "../permissions/Pausable.sol";
import "../mixins/SemVerMixin.sol";
import "./SlashingWithdrawalRouterStorage.sol";

contract SlashingWithdrawalRouter is Initializable, SlashingWithdrawalRouterStorage, Pausable, SemVerMixin {
    using SafeERC20 for IERC20;
    using OperatorSetLib for OperatorSet;

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
        IStrategy strategy,
        uint256 underlyingAmount
    ) external virtual {
        // Assert that the caller is the `StrategyManager`.
        require(msg.sender == address(strategyManager), OnlyStrategyManager());

        // Create a storage pointer to the escrow array.
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Assert that the strategy is not the zero address for sanity.
        require(address(strategy) != address(0), InputAddressZero());

        // Emit the event.
        emit RedistributionInitiated(operatorSet, slashId, strategy, underlyingAmount, uint32(block.number));

        // Update storage.
        escrow.underlyingAmounts.push(underlyingAmount);
        escrow.strategies.push(strategy);
        escrow.startBlock = uint32(block.number);
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function burnOrRedistributeShares(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external virtual onlyWhenNotPaused(PAUSED_BURN_OR_REDISTRIBUTE_SHARES) {
        // Fetch the redistribution recipient for the operator set from the AllocationManager.
        address redistributionRecipient = allocationManager.getRedistributionRecipient(operatorSet);

        // If the redistribution recipient is not the default burn address...
        if (redistributionRecipient != DEFAULT_BURN_ADDRESS) {
            // Assert that the caller is the redistribution recipient.
            require(msg.sender == redistributionRecipient, OnlyRedistributionRecipient());
        }

        // Assert that the escrow is not paused.
        require(!_paused[operatorSet.key()][slashId], RedistributionCurrentlyPaused());

        // Create a storage pointer to the escrow array.
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // // TODO: Implement wrapped delay getter, see DM strategy delay logic.
        // uint32 delay;
        // // Assert that the escrow is mature.
        // require(escrow.startBlock + delay > block.number, RedistributionNotMature());

        // Fetch the length of the escrow array.
        uint256 totalStrategies = escrow.strategies.length;

        // Iterate over the escrow array in reverse order and pop the processed entries from storage.
        for (uint256 i = totalStrategies; i > 0; i--) {
            uint256 index = i - 1;

            // Emit the event.
            emit RedistributionReleased(
                operatorSet, slashId, escrow.strategies[index], escrow.underlyingAmounts[index], redistributionRecipient
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
            escrow.startBlock = 0;
        }
    }

    /// -----------------------------------------------------------------------
    /// Emergency Actions
    /// -----------------------------------------------------------------------

    /// @inheritdoc ISlashingWithdrawalRouter
    function pauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external virtual onlyPauser {
        bool paused = _paused[operatorSet.key()][slashId];

        // Assert that the redistribution is not already paused.
        require(!paused, RedistributionCurrentlyPaused());

        // Set the paused flag to true.
        _paused[operatorSet.key()][slashId] = true;

        // Emit the event.
        emit RedistributionPaused(operatorSet, slashId);
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function unpauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external virtual onlyUnpauser {
        bool paused = _paused[operatorSet.key()][slashId];

        // Assert that the redistribution is already paused.
        require(paused, RedistributionNotPaused());

        // Set the paused flag to false.
        _paused[operatorSet.key()][slashId] = false;

        // Emit the event.
        emit RedistributionUnpaused(operatorSet, slashId);
    }

    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    /// @inheritdoc ISlashingWithdrawalRouter
    function getRedistributionEscrow(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (RedistributionEscrow memory) {
        return _escrow[operatorSet.key()][slashId];
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function isRedistributionPaused(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool) {
        return _paused[operatorSet.key()][slashId];
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function getPendingSlashIdsForOperatorSet(
        OperatorSet calldata operatorSet
    ) external view returns (uint256[] memory) {
        // Get the total number of slashes for this operator set from the allocation manager.
        uint32 slashCount = allocationManager.getSlashCount(operatorSet);

        // Create a temporary array to store all potential slash IDs.
        // We initialize it with the maximum possible size (slashCount).
        uint256[] memory slashIds = new uint256[](slashCount);
        uint256 index = 0;

        // Iterate through all possible slash IDs up to the slash count.
        for (uint32 i = 0; i < slashCount; ++i) {
            // Check if this slash ID has an active escrow (startBlock != 0).
            if (_escrow[operatorSet.key()][i].startBlock != 0) {
                // If active, add it to our array and increment the index.
                slashIds[index++] = i;
            }
        }

        // Use assembly to resize the array to the actual number of active slashes found.
        // This is more gas efficient than creating a new array (requires copying all elements).
        assembly {
            mstore(slashIds, index)
        }

        return slashIds;
    }
}
