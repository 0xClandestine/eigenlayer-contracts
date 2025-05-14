// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin-upgrades/contracts/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAllocationManager.sol";
import "../interfaces/IRedistributionEscrow.sol";

contract RedistributionEscrow is IRedistributionEscrow {
    using SafeERC20 for IERC20;
    using ClonesUpgradeable for *;

    /// @inheritdoc IRedistributionEscrow
    bool public paused;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier checkParameters(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) {
        _checkParameters(implementation, allocationManager, params);
        _;
    }

    modifier onlyAllocationManager(
        IAllocationManager allocationManager
    ) {
        _checkAllocationManager(allocationManager);
        _;
    }

    function _checkParameters(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) internal view virtual {
        require(verify(implementation, allocationManager, params), InvalidParameters());
    }

    function _checkAllocationManager(
        IAllocationManager allocationManager
    ) internal view virtual {
        require(msg.sender == address(allocationManager), OnlyAllocationManager());
    }

    /// -----------------------------------------------------------------------
    /// Actions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IRedistributionEscrow
    function release(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params,
        IERC20 token
    ) external virtual checkParameters(implementation, allocationManager, params) {
        // Assert that the maturity has elapsed.
        require(block.number >= params.maturity, MaturityNotElapsed());

        // Release the funds.
        IERC20(token).safeTransfer(params.recipient, IERC20(token).balanceOf(address(this)));
    }

    /// @inheritdoc IRedistributionEscrow
    function pause(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    )
        external
        virtual
        checkParameters(implementation, allocationManager, params)
        onlyAllocationManager(allocationManager)
    {
        if (!paused) {
            // Pause the escrow.
            paused = true;
            // Emit an event since state was mutated.
            emit Paused();
        }
    }

    /// @inheritdoc IRedistributionEscrow
    function unpause(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    )
        external
        virtual
        checkParameters(implementation, allocationManager, params)
        onlyAllocationManager(allocationManager)
    {
        if (paused) {
            // Unpause the escrow.
            paused = false;
            // Emit an event since state was mutated.
            emit Unpaused();
        }
    }

    /// -----------------------------------------------------------------------
    /// View
    /// -----------------------------------------------------------------------

    /// @inheritdoc IRedistributionEscrow
    function verify(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) public view virtual returns (bool) {
        return ClonesUpgradeable.predictDeterministicAddress({
            implementation: address(implementation),
            salt: computeSalt(params),
            deployer: address(allocationManager)
        }) == address(this);
    }

    /// @inheritdoc IRedistributionEscrow
    function computeSalt(
        SaltParams calldata params
    ) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(params));
    }
}
