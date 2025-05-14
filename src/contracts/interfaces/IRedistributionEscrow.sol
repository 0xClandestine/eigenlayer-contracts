// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IAllocationManager.sol";

interface IRedistributionEscrowErrors {
    /// @notice Thrown when the escrow verification fails.
    error InvalidParameters();
    /// @notice Thrown when the caller is not the AllocationManager.
    error OnlyAllocationManager();
    /// @notice Thrown when the maturity is not elapsed.
    error MaturityNotElapsed();
}

interface IRedistributionEscrowTypes {
    /// @notice Parameters that are hashed to create a create2 salt that determines this contract's address.
    /// @dev Used with ClonesUpgradeable.cloneDeterministic to deploy IRedistributionEscrow contracts at predictable addresses.
    /// @param recipient Address designated to receive the redistributed funds.
    /// @param maturity Block number when funds become available for release.
    struct SaltParams {
        address recipient;
        uint256 maturity;
    }
}

interface IRedistributionEscrowEvents {
    /// @notice Emitted when the escrow is paused.
    event Paused();
    /// @notice Emitted when the escrow is unpaused.
    event Unpaused();
}

interface IRedistributionEscrow is
    IRedistributionEscrowErrors,
    IRedistributionEscrowTypes,
    IRedistributionEscrowEvents
{
    /**
     * @notice Releases the funds.
     * @dev This function is permissionless, anyone can call it once the maturity has elapsed.
     * @param implementation The implementation of this escrow proxy.
     * @param allocationManager The allocation manager.
     * @param params The parameters of the escrow.
     * @param token The token to release.
     */
    function release(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params,
        IERC20 token
    ) external;

    /**
     * @notice Pauses the escrow.
     * @dev The function is permissioned, only the AllocationManager can call it.
     * @param implementation The implementation of this escrow proxy.
     * @param allocationManager The allocation manager.
     * @param params The parameters of the escrow.
     */
    function pause(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) external;

    /**
     * @notice Unpauses the escrow.
     * @dev The function is permissioned, only the AllocationManager can call it.
     * @param implementation The implementation of this escrow proxy.
     * @param allocationManager The allocation manager.
     * @param params The parameters of the escrow.
     */
    function unpause(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) external;

    /**
     * @notice Verifies that the provided initialization parameters of this contract are valid.
     * @param implementation The implementation of this escrow proxy.
     * @param allocationManager The allocation manager.
     * @param params The parameters of the escrow.
     */
    function verify(
        IRedistributionEscrow implementation,
        IAllocationManager allocationManager,
        SaltParams calldata params
    ) external view returns (bool);

    /**
     * @notice Computes the salt for the deterministic address of this contract.
     * @param params The parameters of the escrow.
     */
    function computeSalt(
        SaltParams calldata params
    ) external pure returns (bytes32);

    /**
     * @notice Returns whether the escrow is paused or not.
     */
    function paused() external view returns (bool);
}
