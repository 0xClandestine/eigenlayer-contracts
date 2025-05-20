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
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableMapUpgradeable for EnumerableMapUpgradeable.AddressToUintMap;

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

        // Create storage pointers for readibility.
        EnumerableSetUpgradeable.UintSet storage pendingSlashIds = _pendingSlashIds[operatorSet.key()];
        EnumerableMapUpgradeable.AddressToUintMap storage pendingBurnOrRedistributions =
            _pendingBurnOrRedistributions[operatorSet.key()][slashId];

        // Assert that the strategy is not the zero address for sanity.
        require(address(strategy) != address(0), InputAddressZero());

        // Add the slash ID to the pending slash IDs set.
        pendingSlashIds.add(slashId);

        // Add the strategy and underlying amount to the pending burn or redistributions map.
        pendingBurnOrRedistributions.set(address(strategy), underlyingAmount);

        // Set the start block for the slash ID.
        _slashIdToStartBlock[operatorSet.key()][slashId] = uint32(block.number);

        // Emit the event.
        emit RedistributionInitiated(operatorSet, slashId, strategy, underlyingAmount, uint32(block.number));
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

        // Create storage pointers for readibility.
        EnumerableSetUpgradeable.UintSet storage pendingSlashIds = _pendingSlashIds[operatorSet.key()];
        EnumerableMapUpgradeable.AddressToUintMap storage pendingBurnOrRedistributions =
            _pendingBurnOrRedistributions[operatorSet.key()][slashId];

        // Fetch the length of the escrow array.
        uint256 length = pendingBurnOrRedistributions.length();

        // Iterate over the escrow array in reverse order and pop the processed entries from storage.
        for (uint256 i = length; i > 0; --i) {
            (address strategy, uint256 underlyingAmount) = pendingBurnOrRedistributions.at(i - 1);

            // TODO: delay
            if (true) {
                // Remove the strategy and underlying amount from the pending burn or redistributions map.
                pendingBurnOrRedistributions.remove(strategy);

                // Transfer the escrowed tokens to the caller.
                IStrategy(strategy).underlyingToken().safeTransfer(redistributionRecipient, underlyingAmount);

                // Emit the event.
                emit RedistributionReleased(
                    operatorSet, slashId, IStrategy(strategy), underlyingAmount, redistributionRecipient
                );
            }
        }

        // If there are no more strategies to process, remove the slash ID from the pending slash IDs set.
        if (pendingBurnOrRedistributions.length() == 0) {
            // Remove the slash ID from the pending slash IDs set.
            pendingSlashIds.remove(slashId);

            // Delete the start block for the slash ID.
            delete _slashIdToStartBlock[operatorSet.key()][slashId];
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
    function getPendingSlashIds(
        OperatorSet calldata operatorSet
    ) external view returns (uint256[] memory) {
        return _pendingSlashIds[operatorSet.key()].values();
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function getPendingBurnOrRedistributions(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (IStrategy[] memory strategies, uint256[] memory underlyingAmounts) {
        EnumerableMapUpgradeable.AddressToUintMap storage pendingBurnOrRedistributions =
            _pendingBurnOrRedistributions[operatorSet.key()][slashId];

        uint256 length = pendingBurnOrRedistributions.length();

        strategies = new IStrategy[](length);
        underlyingAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            (address strategy, uint256 underlyingAmount) = pendingBurnOrRedistributions.at(i);

            strategies[i] = IStrategy(strategy);
            underlyingAmounts[i] = underlyingAmount;
        }
    }

    // TODO: nested array version of ^^^

    /// @inheritdoc ISlashingWithdrawalRouter
    function getPendingBurnOrRedistributionsCount(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external view returns (uint256) {
        return _pendingBurnOrRedistributions[operatorSet.key()][slashId].length();
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function getPendingUnderlyingAmountForStrategy(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IStrategy strategy
    ) external view returns (uint256) {
        (, uint256 underlyingAmount) =
            _pendingBurnOrRedistributions[operatorSet.key()][slashId].tryGet(address(strategy));

        return underlyingAmount;
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function isRedistributionPaused(OperatorSet calldata operatorSet, uint256 slashId) external view returns (bool) {
        return _paused[operatorSet.key()][slashId];
    }
}
