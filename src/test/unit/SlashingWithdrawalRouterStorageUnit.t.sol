// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import "src/test/utils/EigenLayerUnitTestSetup.sol";
import "src/contracts/core/SlashingWithdrawalRouter.sol";

// TODO: check getPendingSlashIdsForOperatorSet throughout tests

contract SlashingWithdrawalRouterUnitTests is EigenLayerUnitTestSetup {
    /// @notice The pause status for the `burnOrRedistributeShares` function.
    /// @dev Allows all burn or redistribution outflows to be temporarily halted.
    uint8 public constant PAUSED_BURN_OR_REDISTRIBUTE_SHARES = 0;

    SlashingWithdrawalRouter slashingWithdrawalRouter;

    OperatorSet defaultOperatorSet;
    IStrategy defaultStrategy;
    MockERC20 defaultToken;
    uint defaultSlashId;
    address defaultRedistributionRecipient;

    function setUp() public virtual override {
        EigenLayerUnitTestSetup.setUp();
        slashingWithdrawalRouter = SlashingWithdrawalRouter(
            address(
                new TransparentUpgradeableProxy(
                    address(
                        new SlashingWithdrawalRouter(
                            IAllocationManager(address(allocationManagerMock)),
                            IStrategyManager(address(strategyManagerMock)),
                            IPauserRegistry(address(pauserRegistry)),
                            "1.0.0"
                        )
                    ),
                    address(eigenLayerProxyAdmin),
                    abi.encodeWithSelector(SlashingWithdrawalRouter.initialize.selector, 0)
                )
            )
        );
        defaultOperatorSet = OperatorSet(cheats.randomAddress(), 0);
        defaultStrategy = IStrategy(cheats.randomAddress());
        defaultToken = new MockERC20();
        defaultSlashId = 1;
        defaultRedistributionRecipient = address(cheats.randomAddress());
        allocationManagerMock.setRedistributionRecipient(defaultOperatorSet, defaultRedistributionRecipient);
        cheats.warp(100);
    }

    function _mockStrategyUnderlyingTokenCall(IStrategy strategy, address underlyingToken) internal {
        cheats.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.underlyingToken.selector), abi.encode(underlyingToken));
    }
}

contract SlashingWithdrawalRouterUnitTests_initialize is SlashingWithdrawalRouterUnitTests {
    function test_initialize() public {
        assertEq(address(slashingWithdrawalRouter.allocationManager()), address(allocationManagerMock));
        assertEq(address(slashingWithdrawalRouter.strategyManager()), address(strategyManagerMock));
        assertEq(address(slashingWithdrawalRouter.pauserRegistry()), address(pauserRegistry));
        assertEq(slashingWithdrawalRouter.paused(), 0);
    }
}

contract SlashingWithdrawalRouterUnitTests_startBurnOrRedistributeShares is SlashingWithdrawalRouterUnitTests {
    function test_startBurnOrRedistributeShares_onlyStrategyManager() public {
        cheats.prank(pauser);
        slashingWithdrawalRouter.pause(PAUSED_BURN_OR_REDISTRIBUTE_SHARES);

        cheats.expectRevert(ISlashingWithdrawalRouterErrors.OnlyStrategyManager.selector);
        slashingWithdrawalRouter.startBurnOrRedistributeShares(defaultOperatorSet, defaultSlashId, defaultStrategy, 0);
    }

    function test_startBurnOrRedistributeShares_inputAddressZero() public {
        cheats.prank(address(strategyManagerMock));
        cheats.expectRevert(IPausable.InputAddressZero.selector);
        slashingWithdrawalRouter.startBurnOrRedistributeShares(defaultOperatorSet, defaultSlashId, IStrategy(address(0)), 0);
    }

    function test_startBurnOrRedistributeShares_onlyRedistributionRecipient(uint underlyingAmount) public {
        allocationManagerMock.setRedistributionRecipient(defaultOperatorSet, defaultRedistributionRecipient);

        cheats.prank(address(strategyManagerMock));
        slashingWithdrawalRouter.startBurnOrRedistributeShares(defaultOperatorSet, defaultSlashId, defaultStrategy, underlyingAmount);
        deal(address(defaultToken), address(slashingWithdrawalRouter), underlyingAmount);

        cheats.expectRevert(ISlashingWithdrawalRouterErrors.OnlyRedistributionRecipient.selector);
        slashingWithdrawalRouter.burnOrRedistributeShares(defaultOperatorSet, defaultSlashId);
    }

    function test_startBurnOrRedistributeShares_correctness(uint underlyingAmount) public {
        allocationManagerMock.setRedistributionRecipient(defaultOperatorSet, defaultRedistributionRecipient);

        cheats.prank(address(strategyManagerMock));
        slashingWithdrawalRouter.startBurnOrRedistributeShares(defaultOperatorSet, defaultSlashId, defaultStrategy, underlyingAmount);
        deal(address(defaultToken), address(slashingWithdrawalRouter), underlyingAmount);

        (IStrategy[] memory strategies, uint[] memory amounts) =
            slashingWithdrawalRouter.getPendingBurnOrRedistributions(defaultOperatorSet, defaultSlashId);
        assertEq(strategies.length, 1);
        assertEq(amounts.length, 1);
        assertEq(address(strategies[0]), address(defaultStrategy));
        assertEq(amounts[0], underlyingAmount);

        uint[] memory slashIds = slashingWithdrawalRouter.getPendingSlashIds(defaultOperatorSet);
        assertEq(slashIds.length, 1);
        assertEq(slashIds[0], defaultSlashId);
    }
}

contract SlashingWithdrawalRouterUnitTests_burnOrRedistributeShares is SlashingWithdrawalRouterUnitTests {
    function _startBurnOrRedistributeShares(IStrategy strategy, MockERC20 token, uint underlyingAmount) internal {
        cheats.prank(address(strategyManagerMock));
        slashingWithdrawalRouter.startBurnOrRedistributeShares(defaultOperatorSet, defaultSlashId, strategy, underlyingAmount);
        deal(address(token), address(slashingWithdrawalRouter), underlyingAmount);
    }

    function testFuzz_burnOrRedistributeShares_onlyRedistributionRecipient(uint underlyingAmount) public {
        _startBurnOrRedistributeShares(defaultStrategy, defaultToken, underlyingAmount);
        cheats.expectRevert(ISlashingWithdrawalRouterErrors.OnlyRedistributionRecipient.selector);
        slashingWithdrawalRouter.burnOrRedistributeShares(defaultOperatorSet, defaultSlashId);
    }

    function testFuzz_burnOrRedistributeShares_paused(uint underlyingAmount) public {
        _startBurnOrRedistributeShares(defaultStrategy, defaultToken, underlyingAmount);

        cheats.prank(pauser);
        slashingWithdrawalRouter.pauseRedistribution(defaultOperatorSet, defaultSlashId);

        cheats.prank(defaultRedistributionRecipient);
        cheats.expectRevert(ISlashingWithdrawalRouterErrors.RedistributionCurrentlyPaused.selector);
        slashingWithdrawalRouter.burnOrRedistributeShares(defaultOperatorSet, defaultSlashId);
    }

    function testFuzz_burnOrRedistributeShares_correctness(uint underlyingAmount) public {
        bound(underlyingAmount, 1, type(uint128).max);

        IStrategy strategy2 = IStrategy(cheats.randomAddress());
        MockERC20 token2 = new MockERC20();
        uint underlyingAmount2 = 2 * underlyingAmount;

        _startBurnOrRedistributeShares(defaultStrategy, defaultToken, underlyingAmount);
        _startBurnOrRedistributeShares(strategy2, token2, underlyingAmount2);

        uint[] memory slashIds = slashingWithdrawalRouter.getPendingSlashIds(defaultOperatorSet);
        assertEq(slashIds.length, 1);
        assertEq(slashIds[0], defaultSlashId);

        (IStrategy[] memory strategies, uint[] memory amounts) =
            slashingWithdrawalRouter.getPendingBurnOrRedistributions(defaultOperatorSet, defaultSlashId);
        assertEq(strategies.length, 2);
        assertEq(amounts.length, 2);
        // assertEq(address(strategies[0]), address(defaultStrategy));
        // assertEq(address(strategies[1]), address(strategy2));
        // assertEq(amounts[0], underlyingAmount);
        // assertEq(amounts[1], underlyingAmount2);

        // cheats.prank(defaultRedistributionRecipient);
        // _mockStrategyUnderlyingTokenCall(defaultStrategy, address(defaultToken));
        // _mockStrategyUnderlyingTokenCall(strategy2, address(token2));
        // slashingWithdrawalRouter.burnOrRedistributeShares(defaultOperatorSet, defaultSlashId);

        // assertEq(defaultToken.balanceOf(defaultRedistributionRecipient), underlyingAmount);
        // assertEq(token2.balanceOf(defaultRedistributionRecipient), underlyingAmount2);

        // // Verify the pending slash ID and burn/redistributions are cleared
        // slashIds = slashingWithdrawalRouter.getPendingSlashIds(defaultOperatorSet);
        // assertEq(slashIds.length, 0);

        // (strategies, amounts) = slashingWithdrawalRouter.getPendingBurnOrRedistributions(defaultOperatorSet, defaultSlashId);
        // assertEq(strategies.length, 0);
        // assertEq(amounts.length, 0);
    }
}
