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
    /// Actions
    /// -----------------------------------------------------------------------

    /// @inheritdoc IRedistributionEscrow
    function release(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params,
        IERC20 token
    ) external virtual override {
        // Assert that the provided initialization parameters of this contract are valid.
        require(verify(implementation, allocationManager, params), InvalidEscrow());

        // Assert that the maturity has elapsed.
        require(block.number >= params.maturity, MaturityNotElapsed());

        // Release the funds.
        IERC20(token).safeTransfer(params.recipient, IERC20(token).balanceOf(address(this)));
    }

    /// @inheritdoc IRedistributionEscrow
    function pause(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params,
        string calldata reason
    ) external virtual override {
        // Assert that the provided initialization parameters of this contract are valid.
        require(verify(implementation, allocationManager, params), InvalidEscrow());

        // Assert that the caller is the pauser.
        require(msg.sender == params.pauser, OnlyPauser());

        // Pause the escrow.
        paused = true;

        // Emit an event since state was mutated.
        emit Paused(reason);
    }

    /// -----------------------------------------------------------------------
    /// View
    /// -----------------------------------------------------------------------

    /// @inheritdoc IRedistributionEscrow
    function verify(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) public view virtual override returns (bool) {
        return ClonesUpgradeable.predictDeterministicAddress({
            implementation: address(implementation),
            salt: computeSalt(params),
            deployer: address(allocationManager)
        }) == address(this);
    }

    /// @inheritdoc IRedistributionEscrow
    function computeSalt(
        SaltParams calldata params
    ) public pure virtual override returns (bytes32) {
        return keccak256(abi.encode(params));
    }
}
