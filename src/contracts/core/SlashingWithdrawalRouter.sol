// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/ClonesUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/AccessControlUpgradeable.sol";
import "../mixins/SemVerMixin.sol";
import "./SlashingWithdrawalRouterStorage.sol";

contract SlashingWithdrawalRouter is
    Initializable,
    SlashingWithdrawalRouterStorage,
    AccessControlUpgradeable,
    SemVerMixin
{
    using SafeERC20 for IERC20;
    using OperatorSetLib for OperatorSet;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    /// @dev Checks whether a caller has the `PAUSER_ROLE`.
    modifier onlyPauser() {
        _checkHasRole(PAUSER_ROLE);
        _;
    }

    /// @dev Checks whether a caller has the `UNPAUSER_ROLE`.
    modifier onlyUnpauser() {
        _checkHasRole(UNPAUSER_ROLE);
        _;
    }

    /// @dev Checks whether a caller has the `RELEASER_ROLE` for a given operator set.
    ///     Note that `operatorSet.key()` is also the releaser role key.
    modifier onlyReleaser(
        OperatorSet calldata operatorSet
    ) {
        _checkHasRole(operatorSet.key());
        _;
    }

    /// @dev Checks whether a caller is the `StrategyManager`.
    modifier onlyStrategyManager() {
        _checkOnlyStrategyManager();
        _;
    }

    /// @dev Checks whether a caller has a given role, throws `UnauthorizedCaller` if not.
    function _checkHasRole(
        bytes32 role
    ) internal view virtual {
        require(hasRole(role, msg.sender), UnauthorizedCaller());
    }

    /// @dev Checks whether a caller is the `StrategyManager`, throws `UnauthorizedCaller` if not.
    function _checkOnlyStrategyManager() internal view virtual {
        require(msg.sender == address(strategyManager), UnauthorizedCaller());
    }

    /// -----------------------------------------------------------------------
    /// Initialization
    /// -----------------------------------------------------------------------

    constructor(
        IAllocationManager _allocationManager,
        IStrategyManager _strategyManager,
        string memory _version
    ) SlashingWithdrawalRouterStorage(_allocationManager, _strategyManager) SemVerMixin(_version) {
        _disableInitializers();
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function initialize(address initialAdmin, address initialPauser, address initialUnpauser) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialPauser);
        _grantRole(UNPAUSER_ROLE, initialUnpauser);
    }

    /// -----------------------------------------------------------------------
    /// Actions
    /// -----------------------------------------------------------------------

    /// @inheritdoc ISlashingWithdrawalRouter
    function initiateRedistribution(
        OperatorSet calldata operatorSet,
        uint256 slashId,
        IERC20 token,
        uint256 amount,
        uint32 maturity
    ) external onlyStrategyManager {
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Assert that the token is not the zero address for sanity.
        require(token != IERC20(address(0)), InputAddressZero());

        // Assert that the redistribution does not already exist.
        require(escrow.token == IERC20(address(0)), RedistributionAlreadyExists());

        // Store the escrowed redistribution.
        escrow.amount = amount;
        escrow.token = token;
        escrow.maturity = maturity;

        // Emit the event.
        emit RedistributionInitiated(operatorSet, slashId, token, amount, maturity);
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function releaseRedistribution(
        OperatorSet calldata operatorSet,
        uint256 slashId
    ) external onlyReleaser(operatorSet) {
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Assert that the redistribution is not paused.
        require(!escrow.paused, RedistributionCurrentlyPaused());

        // QUESTION: How do we want to check maturity? Are we storing it during initiation or parsing JIT?

        // Assert that the current block number is greater than or equal to the maturity.
        require(block.number >= escrow.maturity, RedistributionNotMature());

        address redistributionRecipient = allocationManager.getRedistributionRecipient(operatorSet);

        // Transfer the escrowed tokens to the caller.
        escrow.token.safeTransfer(redistributionRecipient, escrow.amount);

        // Set the amount to 0 to prevent double spending.
        escrow.amount = 0;

        // Emit the event.
        emit RedistributionReleased(operatorSet, slashId, escrow.token, escrow.amount, redistributionRecipient);
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function pauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external onlyPauser {
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Assert that the redistribution is not already paused.
        require(!escrow.paused, RedistributionCurrentlyPaused());

        // Set the paused flag to true.
        escrow.paused = true;

        // Emit the event.
        emit RedistributionPaused(operatorSet, slashId);
    }

    /// @inheritdoc ISlashingWithdrawalRouter
    function unpauseRedistribution(OperatorSet calldata operatorSet, uint256 slashId) external onlyUnpauser {
        RedistributionEscrow storage escrow = _escrow[operatorSet.key()][slashId];

        // Assert that the redistribution is already paused.
        require(escrow.paused, RedistributionNotPaused());

        // Set the paused flag to false.
        escrow.paused = false;

        // Emit the event.
        emit RedistributionUnpaused(operatorSet, slashId);
    }
}
