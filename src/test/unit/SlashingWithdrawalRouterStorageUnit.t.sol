// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import "src/test/utils/EigenLayerUnitTestSetup.sol";
import "src/contracts/core/SlashingWithdrawalRouter.sol";

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

        ISlashingWithdrawalRouterTypes.RedistributionEscrow memory escrow =
            slashingWithdrawalRouter.getRedistributionEscrow(defaultOperatorSet, defaultSlashId);

        assertEq(address(escrow.strategies[0]), address(defaultStrategy));
        assertEq(escrow.underlyingAmounts[0], underlyingAmount);
        assertEq(escrow.startBlock, block.number);
    }
}

contract SlashingWithdrawalRouterUnitTests_burnOrRedistributeShares is SlashingWithdrawalRouterUnitTests {
    function _scenario(uint underlyingAmount) internal {
        allocationManagerMock.setRedistributionRecipient(defaultOperatorSet, defaultRedistributionRecipient);

        cheats.prank(address(strategyManagerMock));
        slashingWithdrawalRouter.startBurnOrRedistributeShares(defaultOperatorSet, defaultSlashId, defaultStrategy, underlyingAmount);
        deal(address(defaultToken), address(slashingWithdrawalRouter), underlyingAmount);
    }

    function _mockStrategyUnderlyingTokenCall(IStrategy strategy, address underlyingToken) internal {
        cheats.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.underlyingToken.selector), abi.encode(underlyingToken));
    }

    function test_burnOrRedistributeShares_onlyRedistributionRecipient(uint underlyingAmount) public {
        _scenario(underlyingAmount);
        cheats.expectRevert(ISlashingWithdrawalRouterErrors.OnlyRedistributionRecipient.selector);
        slashingWithdrawalRouter.burnOrRedistributeShares(defaultOperatorSet, defaultSlashId);
    }

    function test_burnOrRedistributeShares_correctness(uint underlyingAmount) public {
        _scenario(underlyingAmount);
        cheats.prank(defaultRedistributionRecipient);
        _mockStrategyUnderlyingTokenCall(defaultStrategy, address(defaultToken));
        slashingWithdrawalRouter.burnOrRedistributeShares(defaultOperatorSet, defaultSlashId);
    }
}
