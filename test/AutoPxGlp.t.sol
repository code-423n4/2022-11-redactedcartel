// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {AutoPxGlp} from "src/vaults/AutoPxGlp.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {PxGmxReward} from "src/vaults/PxGmxReward.sol";
import {Helper} from "./Helper.sol";

contract AutoPxGlpTest is Helper {
    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Compounded(
        address indexed caller,
        uint256 minGlp,
        uint256 wethAmount,
        uint256 pxGmxAmountOut,
        uint256 pxGlpAmountOut,
        uint256 totalPxGlpFee,
        uint256 totalPxGmxFee,
        uint256 pxGlpIncentive,
        uint256 pxGmxIncentive
    );
    event PxGmxClaimed(
        address indexed account,
        address receiver,
        uint256 amount
    );

    /**
        @notice Calculate the global rewards accrued since the last update
        @return uint256  Global rewards
    */
    function _calculateGlobalRewards() internal view returns (uint256) {
        (uint256 lastUpdate, uint256 lastSupply, uint256 rewards) = autoPxGlp
            .globalState();

        return rewards + (block.timestamp - lastUpdate) * lastSupply;
    }

    /**
        @notice Calculate a user's rewards since the last update
        @param  user  address  User
        @return       uint256  User rewards
    */
    function _calculateUserRewards(address user)
        internal
        view
        returns (uint256)
    {
        (uint256 lastUpdate, uint256 lastBalance, uint256 rewards) = autoPxGlp
            .userRewardStates(user);

        return rewards + lastBalance * (block.timestamp - lastUpdate);
    }

    /**
        @notice Perform assertions for global state
        @param  expectedLastUpdate  uint256  Expected last update timestamp
        @param  expectedLastSupply  uint256  Expected last supply
        @param  expectedRewards     uint256  Expected rewards
    */
    function _assertGlobalState(
        uint256 expectedLastUpdate,
        uint256 expectedLastSupply,
        uint256 expectedRewards
    ) internal {
        (uint256 lastUpdate, uint256 lastSupply, uint256 rewards) = autoPxGlp
            .globalState();

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(expectedLastSupply, lastSupply);
        assertEq(expectedRewards, rewards);
    }

    /**
        @notice Perform assertions for user reward state
        @param  user                 address  User address
        @param  expectedLastUpdate   uint256  Expected last update timestamp
        @param  expectedLastBalance  uint256  Expected last user balance
        @param  expectedRewards      uint256  Expected rewards
    */
    function _assertUserRewardState(
        address user,
        uint256 expectedLastUpdate,
        uint256 expectedLastBalance,
        uint256 expectedRewards
    ) internal {
        (uint256 lastUpdate, uint256 lastBalance, uint256 rewards) = autoPxGlp
            .userRewardStates(user);

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(expectedLastBalance, lastBalance);
        assertEq(expectedRewards, rewards);
    }

    /**
        @notice Validate common parameters used for deposits in the tests
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function _validateTestArgs(uint8 multiplier, uint32 secondsElapsed)
        internal
    {
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
    }

    /**
        @notice Perform common setup for reward accrual and test accounts for vault tests
        @param  multiplier  uint8  Multiplied with fixed token amounts for randomness
     */
    function _setupRewardsAndTestAccounts(uint8 multiplier) internal {
        pirexRewards.addRewardToken(pxGmx, weth);
        pirexRewards.addRewardToken(pxGmx, pxGmx);
        pirexRewards.addRewardToken(pxGlp, weth);
        pirexRewards.addRewardToken(pxGlp, pxGmx);

        // Some tests require different deposit setup, only process those with non-zero multiplier
        if (multiplier > 0) {
            _depositGlpForTestAccounts(true, address(this), multiplier, true);
        }
    }

    /**
        @notice Perform deposit to the vault
        @param  user  address  User address
        @return       uint256  Amount of shares
     */
    function _depositToVault(address user) internal returns (uint256) {
        vm.startPrank(user);

        pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(user));

        uint256 shares = autoPxGlp.deposit(pxGlp.balanceOf(user), user);

        vm.stopPrank();

        return shares;
    }

    /**
        @notice Calculate amount of accrued rewards by the vault
        @param  rewardState  uint256  Reward state
        @param  vaultState   uint256  Vault state
        @param  globalState  uint256  Global state
        @return              uint256  Amount of rewards
     */
    function _calculateVaultReward(
        uint256 rewardState,
        uint256 vaultState,
        uint256 globalState
    ) internal pure returns (uint256) {
        if (globalState != 0) {
            return (rewardState * vaultState) / globalState;
        }

        return 0;
    }

    /**
        @notice Provision reward state to test compounding of rewards
        @param  secondsElapsed    uint256  Seconds to forward timestamp
        @return wethRewardState   uint256  WETH reward state
        @return pxGmxRewardState  uint256  pxGMX reward state
     */
    function _provisionRewardState(uint256 secondsElapsed)
        internal
        returns (uint256 wethRewardState, uint256 pxGmxRewardState)
    {
        // Time skip to accrue rewards then return the latest reward states
        vm.warp(block.timestamp + secondsElapsed);

        pirexRewards.harvest();

        // Take into account rewards from both pxGMX and pxGLP based on the vault's current shares
        uint256 pxGmxGlobalRewards = _calculateGlobalRewards(pxGmx);
        uint256 pxGlpGlobalRewards = _calculateGlobalRewards(pxGlp);
        uint256 pxGmxVaultRewards = _calculateUserRewards(
            pxGmx,
            address(autoPxGlp)
        );
        uint256 pxGlpVaultRewards = _calculateUserRewards(
            pxGlp,
            address(autoPxGlp)
        );

        wethRewardState =
            _calculateVaultReward(
                pirexRewards.getRewardState(pxGmx, weth),
                pxGmxVaultRewards,
                pxGmxGlobalRewards
            ) +
            _calculateVaultReward(
                pirexRewards.getRewardState(pxGlp, weth),
                pxGlpVaultRewards,
                pxGlpGlobalRewards
            );
        pxGmxRewardState =
            _calculateVaultReward(
                pirexRewards.getRewardState(pxGmx, pxGmx),
                pxGmxVaultRewards,
                pxGmxGlobalRewards
            ) +
            _calculateVaultReward(
                pirexRewards.getRewardState(pxGlp, pxGmx),
                pxGlpVaultRewards,
                pxGlpGlobalRewards
            );
    }

    /**
        @notice Compound and perform assertions partially
        @return wethAmount      uint256  WETH amount
        @return pxGmxAmount     uint256  pxGMX amount
        @return pxGlpAmount     uint256  pxGLP amount
        @return pxGlpFee        uint256  pxGLP fee
        @return pxGlpInc        uint256  pxGLP incentive
        @return pxGmxFee        uint256  pxGMX fee
    */
    function _compoundAndAssert()
        internal
        returns (
            uint256 wethAmount,
            uint256 pxGmxAmount,
            uint256 pxGlpAmount,
            uint256 pxGlpFee,
            uint256 pxGlpInc,
            uint256 pxGmxFee
        )
    {
        uint256 preCompoundOwnerBalance = pxGmx.balanceOf(autoPxGlp.owner());
        uint256 preCompoundCompounderBalance = pxGmx.balanceOf(testAccounts[0]);

        vm.expectEmit(true, false, false, false, address(autoPxGlp));

        emit Compounded(testAccounts[0], 0, 0, 0, 0, 0, 0, 0, 0);

        // Call as testAccounts[0] to test compound incentive transfer
        vm.prank(testAccounts[0]);

        (
            uint256 wethAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut,
            uint256 totalPxGlpFee,
            uint256 totalPxGmxFee,
            uint256 pxGlpIncentive,
            uint256 pxGmxIncentive
        ) = autoPxGlp.compound(1, 1, false);

        // Assert updated states separately (stack-too-deep issue)
        _assertPostCompoundPxGmxRewardStates(
            preCompoundOwnerBalance,
            preCompoundCompounderBalance,
            pxGmxAmountOut,
            totalPxGmxFee,
            pxGmxIncentive
        );

        wethAmount = wethAmountIn;
        pxGmxAmount = pxGmxAmountOut;
        pxGlpAmount = pxGlpAmountOut;
        pxGlpFee = totalPxGlpFee;
        pxGlpInc = pxGlpIncentive;
        pxGmxFee = totalPxGmxFee;
    }

    /**
        @notice Assert main vault states after performing compound
        @param  user                       address  Test user address
        @param  pxGlpAmountOut             uint256  pxGLP rewards before fees
        @param  totalPxGlpFee              uint256  Total fees for pxGLP
        @param  pxGlpIncentive             uint256  Incentive for pxGLP
        @param  totalAssetsBeforeCompound  uint256  Total assets before compound
     */
    function _assertPostCompoundVaultStates(
        address user,
        uint256 pxGlpAmountOut,
        uint256 totalPxGlpFee,
        uint256 pxGlpIncentive,
        uint256 totalAssetsBeforeCompound
    ) internal {
        uint256 userShareBalance = autoPxGlp.balanceOf(user);
        uint256 expectedTotalPxGlpFee = (pxGlpAmountOut *
            autoPxGlp.platformFee()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedCompoundIncentive = (totalPxGlpFee *
            autoPxGlp.compoundIncentive()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedTotalAssets = totalAssetsBeforeCompound +
            pxGlpAmountOut -
            totalPxGlpFee;

        assertGt(expectedTotalAssets, totalAssetsBeforeCompound);
        assertEq(expectedTotalAssets, autoPxGlp.totalAssets());
        assertEq(expectedTotalAssets, pxGlp.balanceOf(address(autoPxGlp)));
        assertEq(expectedTotalPxGlpFee, totalPxGlpFee);
        assertEq(expectedCompoundIncentive, pxGlpIncentive);
        assertEq(
            expectedTotalPxGlpFee -
                expectedCompoundIncentive +
                expectedCompoundIncentive,
            totalPxGlpFee
        );
        assertEq(userShareBalance, autoPxGlp.balanceOf(user));
    }

    /**
        @notice Assert pxGMX reward states after performing compound
        @param  preCompoundOwnerBalance       uint256  Pre-compound owner pxGmx balance
        @param  preCompoundCompounderBalance  uint256  Pre-compound compounder pxGmx balance
        @param  pxGmxAmountOut                uint256  pxGMX rewards before fees
        @param  totalPxGmxFee                 uint256  Total fees for pxGMX
        @param  pxGmxIncentive                uint256  Incentive for pxGMX
     */
    function _assertPostCompoundPxGmxRewardStates(
        uint256 preCompoundOwnerBalance,
        uint256 preCompoundCompounderBalance,
        uint256 pxGmxAmountOut,
        uint256 totalPxGmxFee,
        uint256 pxGmxIncentive
    ) internal {
        uint256 expectedTotalPxGmxFee = (pxGmxAmountOut *
            autoPxGlp.platformFee()) / autoPxGlp.FEE_DENOMINATOR();
        uint256 expectedCompoundPxGmxIncentive = (totalPxGmxFee *
            autoPxGlp.compoundIncentive()) / autoPxGlp.FEE_DENOMINATOR();
        assertEq(expectedTotalPxGmxFee, totalPxGmxFee);
        assertEq(expectedCompoundPxGmxIncentive, pxGmxIncentive);

        // Check for pxGMX reward balances of the fee receivers
        assertEq(
            preCompoundOwnerBalance +
                expectedTotalPxGmxFee -
                expectedCompoundPxGmxIncentive,
            pxGmx.balanceOf(autoPxGlp.owner())
        );
        assertEq(
            preCompoundCompounderBalance + expectedCompoundPxGmxIncentive,
            pxGmx.balanceOf(testAccounts[0])
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setWithdrawalPenalty TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetWithdrawalPenaltyUnauthorized() external {
        // Define function arguments
        uint256 penalty = 1;

        // Define post-transition/upcoming state or effects
        vm.expectRevert("UNAUTHORIZED");

        // Execute state transition
        vm.prank(testAccounts[0]);

        autoPxGlp.setWithdrawalPenalty(penalty);
    }

    /**
        @notice Test tx reversion: penalty exceeds max
     */
    function testCannotSetWithdrawalPenaltyExceedsMax() external {
        uint256 invalidPenalty = autoPxGlp.MAX_WITHDRAWAL_PENALTY() + 1;

        vm.expectRevert(AutoPxGlp.ExceedsMax.selector);

        autoPxGlp.setWithdrawalPenalty(invalidPenalty);
    }

    /**
        @notice Test tx success: set withdrawal penalty
     */
    function testSetWithdrawalPenalty() external {
        uint256 initialWithdrawalPenalty = autoPxGlp.withdrawalPenalty();
        uint256 penalty = 1;
        uint256 expectedWithdrawalPenalty = penalty;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit WithdrawalPenaltyUpdated(expectedWithdrawalPenalty);

        autoPxGlp.setWithdrawalPenalty(penalty);

        assertEq(expectedWithdrawalPenalty, autoPxGlp.withdrawalPenalty());
        assertTrue(expectedWithdrawalPenalty != initialWithdrawalPenalty);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatformFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPlatformFeeUnauthorized() external {
        uint256 fee = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGlp.setPlatformFee(fee);
    }

    /**
        @notice Test tx reversion: fee exceeds max
     */
    function testCannotSetPlatformFeeExceedsMax() external {
        uint256 invalidFee = autoPxGlp.MAX_PLATFORM_FEE() + 1;

        vm.expectRevert(AutoPxGlp.ExceedsMax.selector);

        autoPxGlp.setPlatformFee(invalidFee);
    }

    /**
        @notice Test tx success: set platform fee
     */
    function testSetPlatformFee() external {
        uint256 initialPlatformFee = autoPxGlp.platformFee();
        uint256 fee = 1;
        uint256 expectedPlatformFee = fee;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit PlatformFeeUpdated(expectedPlatformFee);

        autoPxGlp.setPlatformFee(fee);

        assertEq(expectedPlatformFee, autoPxGlp.platformFee());
        assertTrue(expectedPlatformFee != initialPlatformFee);
    }

    /*//////////////////////////////////////////////////////////////
                        setCompoundIncentive TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetCompoundIncentiveUnauthorized() external {
        uint256 incentive = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGlp.setCompoundIncentive(incentive);
    }

    /**
        @notice Test tx reversion: incentive exceeds max
     */
    function testCannotSetCompoundIncentiveExceedsMax() external {
        uint256 invalidIncentive = autoPxGlp.MAX_COMPOUND_INCENTIVE() + 1;

        vm.expectRevert(AutoPxGlp.ExceedsMax.selector);

        autoPxGlp.setCompoundIncentive(invalidIncentive);
    }

    /**
        @notice Test tx success: set compound incentive percent
     */
    function testSetCompoundIncentive() external {
        uint256 initialCompoundIncentive = autoPxGlp.compoundIncentive();
        uint256 incentive = 1;
        uint256 expectedCompoundIncentive = incentive;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit CompoundIncentiveUpdated(expectedCompoundIncentive);

        autoPxGlp.setCompoundIncentive(incentive);

        assertEq(expectedCompoundIncentive, autoPxGlp.compoundIncentive());
        assertTrue(expectedCompoundIncentive != initialCompoundIncentive);
    }

    /*//////////////////////////////////////////////////////////////
                        setPlatform TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPlatformUnauthorized() external {
        address platform = address(this);

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGlp.setPlatform(platform);
    }

    /**
        @notice Test tx reversion: platform is zero address
     */
    function testCannotSetPlatformZeroAddress() external {
        address invalidPlatform = address(0);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.setPlatform(invalidPlatform);
    }

    /**
        @notice Test tx success: set platform
     */
    function testSetPlatform() external {
        address initialPlatform = autoPxGlp.platform();
        address platform = address(this);
        address expectedPlatform = platform;

        vm.expectEmit(false, false, false, true, address(autoPxGlp));

        emit PlatformUpdated(expectedPlatform);

        autoPxGlp.setPlatform(platform);

        assertEq(expectedPlatform, autoPxGlp.platform());
        assertTrue(expectedPlatform != initialPlatform);
    }

    /*//////////////////////////////////////////////////////////////
                        totalAssets TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: return the total assets
        @param  multiplier  uint8  Multiplied with fixed token amounts for randomness
    */
    function testTotalAssets(uint8 multiplier) external {
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        uint256 initialTotalAssets = autoPxGlp.totalAssets();

        uint256 totalDeposit;
        uint256[] memory depositAmounts = _depositGlpForTestAccounts(
            false,
            address(this),
            multiplier,
            true
        );

        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];

            vm.startPrank(testAccount);

            pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(testAccount));
            autoPxGlp.deposit(pxGlp.balanceOf(testAccount), testAccount);

            vm.stopPrank();

            totalDeposit += depositAmounts[i];
        }

        uint256 assets = pxGlp.balanceOf(address(autoPxGlp));

        assertEq(assets, autoPxGlp.totalAssets());
        assertTrue(assets != initialTotalAssets);
    }

    /*//////////////////////////////////////////////////////////////
                        compound TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: minUsdg is invalid (zero)
     */
    function testCannotCompoundMinUsdgInvalidParam() external {
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGlp.InvalidParam.selector);

        autoPxGlp.compound(invalidMinUsdg, minGlp, optOutIncentive);
    }

    /**
        @notice Test tx reversion: minGlp is invalid (zero)
     */
    function testCannotCompoundMinGlpInvalidParam() external {
        uint256 minUsdg = 1;
        uint256 invalidMinGlpAmount = 0;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGlp.InvalidParam.selector);

        autoPxGlp.compound(minUsdg, invalidMinGlpAmount, optOutIncentive);
    }

    /**
        @notice Test tx success: compound pxGLP rewards into more pxGLP and track pxGMX reward states
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testCompound(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(multiplier);

        for (uint256 i; i < testAccounts.length; ++i) {
            _depositToVault(testAccounts[i]);

            (
                uint256 wethRewardState,
                uint256 pxGmxRewardState
            ) = _provisionRewardState(secondsElapsed);

            uint256 totalAssetsBeforeCompound = autoPxGlp.totalAssets();
            uint256 pxGmxBalanceBeforeCompound = pxGmx.balanceOf(
                address(autoPxGlp)
            );
            uint256 pxGlpOwnerBalanceBeforeCompound = pxGlp.balanceOf(
                autoPxGlp.owner()
            );
            // Commented out due to Stack-too-deep
            // uint256 pxGlpCompounderBalanceBeforeCompound = pxGlp.balanceOf(
            //     testAccounts[0]
            // );
            uint256 expectedGlobalLastSupply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();

            assertGt(wethRewardState, 0);

            // Perform compound and assertions partially (stack-too-deep)
            (
                uint256 wethAmountIn,
                uint256 pxGmxAmountOut,
                uint256 pxGlpAmountOut,
                uint256 totalPxGlpFee,
                uint256 pxGlpIncentive,
                uint256 totalPxGmxFee
            ) = _compoundAndAssert();

            // Perform the rest of the assertions (stack-too-deep)
            assertEq(wethRewardState, wethAmountIn);
            assertEq(pxGmxRewardState, pxGmxAmountOut);

            _assertGlobalState(
                block.timestamp,
                expectedGlobalLastSupply,
                expectedGlobalRewards
            );

            _assertPostCompoundVaultStates(
                testAccounts[i],
                pxGlpAmountOut,
                totalPxGlpFee,
                pxGlpIncentive,
                totalAssetsBeforeCompound
            );

            assertEq(
                (pxGmxAmountOut - totalPxGmxFee),
                pxGmx.balanceOf(address(autoPxGlp)) - pxGmxBalanceBeforeCompound
            );

            // Check for vault asset balances of the fee receivers
            assertEq(
                pxGlpOwnerBalanceBeforeCompound +
                    totalPxGlpFee -
                    pxGlpIncentive,
                pxGlp.balanceOf(autoPxGlp.owner())
            );
            // Commented out due to Stack-too-deep
            // assertEq(
            //     pxGlpCompounderBalanceBeforeCompound + pxGlpIncentive,
            //     pxGlp.balanceOf(testAccounts[0])
            // );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        deposit TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: deposit to vault and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testDeposit(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(multiplier);

        for (uint256 i; i < testAccounts.length; ++i) {
            _depositToVault(testAccounts[i]);

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);
            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedLastUpdate = block.timestamp;
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 pxGmxRewardAfterFees = pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

            // Perform another deposit and assert the updated pxGMX reward states
            _depositGlpETHWithTimeSkip(
                (1 ether * (i + 1) * multiplier),
                testAccounts[i],
                0
            );

            uint256 newShares = _depositToVault(testAccounts[i]);

            // Assert pxGMX reward states
            _assertGlobalState(
                expectedLastUpdate,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                expectedLastUpdate,
                initialBalance + newShares,
                expectedUserRewardState
            );
            assertEq(
                initialRewardState + pxGmxRewardAfterFees,
                autoPxGlp.rewardState()
            );

            // Deposit should still increment the totalSupply and user shares
            assertEq(supply + newShares, autoPxGlp.totalSupply());
            assertEq(
                initialBalance + newShares,
                autoPxGlp.balanceOf(testAccounts[i])
            );

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance + pxGmxRewardAfterFees,
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        depositFsGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: fsGLP amount is zero
     */
    function testCannotDepositFsGlpZeroAmount() external {
        uint256 invalidAmount = 0;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositFsGlp(invalidAmount, receiver);
    }

    /**
        @notice Test tx reversion: fsGLP amount is zero
     */
    function testCannotDepositFsGlpZeroAddress() external {
        uint256 amount = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.depositFsGlp(amount, invalidReceiver);
    }

    /**
        @notice Test tx success: deposit using fsGLP to vault and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testDepositFsGlp(uint8 multiplier, uint32 secondsElapsed)
        external
    {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(0);

        for (uint256 i; i < testAccounts.length; ++i) {
            // Mint fsGLP for the testAccount then deposit to the vault
            uint256 fsGlpBalance = _mintAndApproveFsGlp(
                multiplier * 1 ether,
                testAccounts[i]
            );

            vm.startPrank(testAccounts[i]);

            STAKED_GLP.approve(address(autoPxGlp), fsGlpBalance);

            vm.expectEmit(true, true, false, false, address(autoPxGlp));

            emit Deposit(testAccounts[i], testAccounts[i], 0, 0);

            autoPxGlp.depositFsGlp(fsGlpBalance, testAccounts[i]);

            vm.stopPrank();

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);

            // Make sure that the actual minted shares is correct
            assertEq(
                initialBalance,
                autoPxGlp.previewDeposit(
                    fsGlpBalance -
                        (fsGlpBalance * pirexGmx.fees(PirexGmx.Fees.Deposit)) /
                        pirexGmx.FEE_DENOMINATOR()
                )
            );

            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 pxGmxRewardAfterFees = pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

            // Perform another deposit and assert the updated pxGMX reward states
            _depositGlpETHWithTimeSkip(
                (1 ether * (i + 1) * multiplier),
                testAccounts[i],
                0
            );

            uint256 newShares = _depositToVault(testAccounts[i]);

            // Assert pxGMX reward states
            _assertGlobalState(
                block.timestamp,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                block.timestamp,
                initialBalance + newShares,
                expectedUserRewardState
            );
            assertEq(
                initialRewardState + pxGmxRewardAfterFees,
                autoPxGlp.rewardState()
            );

            // Deposit should still increment the totalSupply and user shares
            assertEq(supply + newShares, autoPxGlp.totalSupply());
            assertEq(
                initialBalance + newShares,
                autoPxGlp.balanceOf(testAccounts[i])
            );

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance + pxGmxRewardAfterFees,
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: token address is the zero address
     */
    function testCannotDepositGlpTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.depositGlp(
            invalidToken,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: token amount is zero
     */
    function testCannotDepositGlpTokenZeroAmount() external {
        address token = address(weth);
        uint256 invalidTokenAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositGlp(
            token,
            invalidTokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpMinUsdgZeroAmount() external {
        address token = address(weth);
        uint256 tokenAmount = 1;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositGlp(
            token,
            tokenAmount,
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpMinGlpZeroAmount() external {
        address token = address(weth);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is the zero address
     */
    function testCannotDepositGlpReceiverZeroAddress() external {
        address token = address(weth);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx success: deposit using whitelisted token to vault and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testDepositGlp(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(0);

        for (uint256 i; i < testAccounts.length; ++i) {
            // Mint WETH for the testAccount then deposit to the vault
            vm.deal(address(this), multiplier * 1 ether);

            _mintWrappedToken(multiplier * 1 ether, testAccounts[i]);

            vm.startPrank(testAccounts[i]);

            weth.approve(address(autoPxGlp), weth.balanceOf(testAccounts[i]));

            vm.expectEmit(true, true, false, false, address(autoPxGlp));

            emit Deposit(testAccounts[i], testAccounts[i], 0, 0);

            autoPxGlp.depositGlp(
                address(weth),
                weth.balanceOf(testAccounts[i]),
                1,
                1,
                testAccounts[i]
            );

            vm.stopPrank();

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);
            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 pxGmxRewardAfterFees = pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

            // Perform another deposit and assert the updated pxGMX reward states
            _depositGlpETHWithTimeSkip(
                (1 ether * (i + 1) * multiplier),
                testAccounts[i],
                0
            );

            uint256 newShares = _depositToVault(testAccounts[i]);

            // Assert pxGMX reward states
            _assertGlobalState(
                block.timestamp,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                block.timestamp,
                initialBalance + newShares,
                expectedUserRewardState
            );
            assertEq(
                initialRewardState + pxGmxRewardAfterFees,
                autoPxGlp.rewardState()
            );

            // Deposit should still increment the totalSupply and user shares
            assertEq(supply + newShares, autoPxGlp.totalSupply());
            assertEq(
                initialBalance + newShares,
                autoPxGlp.balanceOf(testAccounts[i])
            );

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance + pxGmxRewardAfterFees,
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: msg.value is zero
     */
    function testCannotDepositGlpETHValueZeroAmount() external {
        uint256 invalidAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositGlpETH{value: invalidAmount}(
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpETHMinUsdgZeroAmount() external {
        uint256 amount = 1;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositGlpETH{value: amount}(
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpETHMinGlpZeroAmount() external {
        uint256 amount = 1;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.expectRevert(AutoPxGlp.ZeroAmount.selector);

        autoPxGlp.depositGlpETH{value: amount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is the zero address
     */
    function testCannotDepositGlpETHReceiverZeroAddress() external {
        uint256 amount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.depositGlpETH{value: amount}(
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx success: deposit using ETH to vault and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testDepositGlpETH(uint8 multiplier, uint32 secondsElapsed)
        external
    {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(0);

        for (uint256 i; i < testAccounts.length; ++i) {
            // Deal ETH for the testAccount then deposit to the vault
            uint256 ethAmount = multiplier * 1 ether;

            vm.deal(testAccounts[i], ethAmount);

            vm.startPrank(testAccounts[i]);

            vm.expectEmit(true, true, false, false, address(autoPxGlp));

            emit Deposit(testAccounts[i], testAccounts[i], 0, 0);

            autoPxGlp.depositGlpETH{value: ethAmount}(1, 1, testAccounts[i]);

            vm.stopPrank();

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);
            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 pxGmxRewardAfterFees = pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

            // Perform another deposit and assert the updated pxGMX reward states
            _depositGlpETHWithTimeSkip(
                (1 ether * (i + 1) * multiplier),
                testAccounts[i],
                0
            );

            uint256 newShares = _depositToVault(testAccounts[i]);

            // Assert pxGMX reward states
            _assertGlobalState(
                block.timestamp,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                block.timestamp,
                initialBalance + newShares,
                expectedUserRewardState
            );
            assertEq(
                initialRewardState + pxGmxRewardAfterFees,
                autoPxGlp.rewardState()
            );

            // Deposit should still increment the totalSupply and user shares
            assertEq(supply + newShares, autoPxGlp.totalSupply());
            assertEq(
                initialBalance + newShares,
                autoPxGlp.balanceOf(testAccounts[i])
            );

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance + pxGmxRewardAfterFees,
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        mint TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: mint vault shares and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testMint(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(multiplier);

        for (uint256 i; i < testAccounts.length; ++i) {
            _depositToVault(testAccounts[i]);

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);
            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 pxGmxRewardAfterFees = pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

            // Perform mint instead of deposit and assert the updated pxGMX reward states
            _depositGlpETHWithTimeSkip(
                (1 ether * (i + 1) * multiplier),
                testAccounts[i],
                0
            );

            vm.startPrank(testAccounts[i]);

            pxGlp.approve(address(autoPxGlp), pxGlp.balanceOf(testAccounts[i]));

            uint256 newShares = autoPxGlp.previewDeposit(
                pxGlp.balanceOf(testAccounts[i])
            ) / 2;

            autoPxGlp.mint(newShares, testAccounts[i]);

            vm.stopPrank();

            // Assert pxGMX reward states
            _assertGlobalState(
                block.timestamp,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                block.timestamp,
                initialBalance + newShares,
                expectedUserRewardState
            );
            assertEq(
                autoPxGlp.rewardState(),
                initialRewardState + pxGmxRewardAfterFees
            );

            // Mint should still increment the totalSupply and user shares
            assertEq(supply + newShares, autoPxGlp.totalSupply());
            assertEq(
                initialBalance + newShares,
                autoPxGlp.balanceOf(testAccounts[i])
            );

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance + pxGmxRewardAfterFees,
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        withdraw TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: withdraw from vault and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testWithdraw(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(multiplier);

        for (uint256 i; i < testAccounts.length; ++i) {
            _depositToVault(testAccounts[i]);

            (
                uint256 wethRewardState,
                uint256 pxGmxRewardState
            ) = _provisionRewardState(secondsElapsed);

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);
            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));
            uint256 expectedAdditionalGlp = _calculateMinGlpAmount(
                address(weth),
                wethRewardState,
                18
            );
            // Take into account fees
            expectedAdditionalGlp -=
                (expectedAdditionalGlp * pirexGmx.fees(PirexGmx.Fees.Deposit)) /
                pirexGmx.FEE_DENOMINATOR();
            expectedAdditionalGlp -=
                (expectedAdditionalGlp * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();

            // Withdraw from the vault and assert the updated pxGMX reward states
            vm.startPrank(testAccounts[i]);

            // Take into account additional glp from compound and withdraw all
            uint256 shares = autoPxGlp.withdraw(
                autoPxGlp.previewRedeem(initialBalance) + expectedAdditionalGlp,
                testAccounts[i],
                testAccounts[i]
            );

            vm.stopPrank();

            // Since we withdraw the entire balance of the user, post-withdrawal should leave it with 0 share
            assertEq(0, autoPxGlp.balanceOf(testAccounts[i]));

            // Assert pxGMX reward states
            _assertGlobalState(
                block.timestamp,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                block.timestamp,
                initialBalance - shares,
                expectedUserRewardState
            );
            assertEq(
                initialRewardState +
                    (pxGmxRewardState -
                        (pxGmxRewardState * autoPxGlp.platformFee()) /
                        autoPxGlp.FEE_DENOMINATOR()),
                autoPxGlp.rewardState()
            );

            // Withdrawal should still decrement the totalSupply and user shares
            assertEq(supply - shares, autoPxGlp.totalSupply());
            assertEq(
                initialBalance - shares,
                autoPxGlp.balanceOf(testAccounts[i])
            );

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance +
                    (pxGmxRewardState -
                        (pxGmxRewardState * autoPxGlp.platformFee()) /
                        autoPxGlp.FEE_DENOMINATOR()),
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        redeem TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: redeem from vault and assert the pxGMX reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testRedeem(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(multiplier);

        for (uint256 i; i < testAccounts.length; ++i) {
            _depositToVault(testAccounts[i]);

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 initialBalance = autoPxGlp.balanceOf(testAccounts[i]);
            uint256 initialRewardState = autoPxGlp.rewardState();
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedGlobalRewards = _calculateGlobalRewards();
            uint256 expectedUserRewardState = _calculateUserRewards(
                testAccounts[i]
            );
            uint256 pxGmxRewardAfterFees = pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 initialPxGmxBalance = pxGmx.balanceOf(address(autoPxGlp));

            // Redeem from the vault and assert the updated pxGMX reward states
            vm.prank(testAccounts[i]);

            autoPxGlp.redeem(initialBalance, testAccounts[i], testAccounts[i]);

            // Assert pxGMX reward states
            _assertGlobalState(
                block.timestamp,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards
            );
            _assertUserRewardState(
                testAccounts[i],
                block.timestamp,
                0,
                expectedUserRewardState
            );
            assertEq(
                initialRewardState + pxGmxRewardAfterFees,
                autoPxGlp.rewardState()
            );

            // Redemption should still decrement the totalSupply and user shares
            assertEq(supply - initialBalance, autoPxGlp.totalSupply());
            assertEq(0, autoPxGlp.balanceOf(testAccounts[i]));

            // Also check the updated pxGMX balance updated from compound call
            assertEq(
                initialPxGmxBalance + pxGmxRewardAfterFees,
                pxGmx.balanceOf(address(autoPxGlp))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        claim TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotClaimZeroAddress() external {
        address invalidReceiver = address(0);

        vm.expectRevert(PxGmxReward.ZeroAddress.selector);

        autoPxGlp.claim(invalidReceiver);
    }

    /**
        @notice Test tx success: claim pxGMX rewards and assert the reward states updates
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testClaim(uint8 multiplier, uint32 secondsElapsed) external {
        _validateTestArgs(multiplier, secondsElapsed);

        _setupRewardsAndTestAccounts(multiplier);

        uint256 totalClaimable;

        for (uint256 i; i < testAccounts.length; ++i) {
            address account = testAccounts[i];
            address receiver = testAccounts[i];

            _depositToVault(account);

            (, uint256 pxGmxRewardState) = _provisionRewardState(
                secondsElapsed
            );

            uint256 pxGmxBalanceBeforeClaim = pxGmx.balanceOf(receiver);
            uint256 expectedLastBalance = autoPxGlp.balanceOf(account);
            uint256 expectedGlobalLastUpdate = block.timestamp;
            uint256 expectedGlobalRewards = _calculateGlobalRewards();

            totalClaimable +=
                pxGmxRewardState -
                (pxGmxRewardState * autoPxGlp.platformFee()) /
                autoPxGlp.FEE_DENOMINATOR();
            uint256 expectedUserRewardState = _calculateUserRewards(account);
            uint256 expectedClaimableReward = (totalClaimable *
                expectedUserRewardState) / expectedGlobalRewards;

            // Event is only logged when rewards exists (ie. non-zero esGMX yields)
            if (expectedClaimableReward != 0) {
                vm.expectEmit(true, false, false, false, address(autoPxGlp));

                emit PxGmxClaimed(account, receiver, 0);
            }

            // Claim pxGMX reward from the vault and transfer it to the receiver directly
            vm.prank(account);

            autoPxGlp.claim(receiver);

            // Claiming should also update the pxGMX balance for the receiver and the reward state
            assertEq(
                expectedClaimableReward + pxGmxBalanceBeforeClaim,
                pxGmx.balanceOf(receiver)
            );
            _assertGlobalState(
                expectedGlobalLastUpdate,
                autoPxGlp.totalSupply(),
                expectedGlobalRewards - expectedUserRewardState
            );
            _assertUserRewardState(
                account,
                block.timestamp,
                expectedLastBalance,
                0
            );

            // Properly update the total tally of claimable pxGMX
            totalClaimable -= expectedClaimableReward;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        transfer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: transfer (or transferFrom) to another account and assert the pxGMX reward states
        @param  multiplier          uint8   Multiplied with fixed token amounts for randomness
        @param  transferPercentage  uint8   Percentage of sender balance to be transferred
        @param  secondsElapsed      uint32  Seconds to forward timestamp
        @param  useTransferFrom     bool    Whether to use transferFrom
     */
    function testTransfer(
        uint8 multiplier,
        uint8 transferPercentage,
        uint32 secondsElapsed,
        bool useTransferFrom
    ) external {
        _validateTestArgs(multiplier, secondsElapsed);

        vm.assume(transferPercentage != 0);
        vm.assume(transferPercentage <= 100);

        _setupRewardsAndTestAccounts(multiplier);

        for (uint256 i; i < testAccounts.length; ++i) {
            address account = testAccounts[i];
            address receiver = testAccounts[
                (i < testAccounts.length - 1 ? i + 1 : 0)
            ];

            _depositToVault(account);

            _provisionRewardState(secondsElapsed);

            uint256 initialSenderBalance = autoPxGlp.balanceOf(account);
            uint256 initialReceiverBalance = autoPxGlp.balanceOf(receiver);
            uint256 supply = autoPxGlp.totalSupply();
            uint256 expectedLastUpdate = block.timestamp;
            uint256 expectedSenderRewardState = _calculateUserRewards(account);
            uint256 expectedReceiverRewardState = _calculateUserRewards(
                receiver
            );

            // Transfer certain percentages of the apxGLP holding to the other account
            uint256 transferAmount = (initialSenderBalance *
                transferPercentage) / 100;
            uint256 expectedSenderBalance = initialSenderBalance -
                transferAmount;
            uint256 expectedReceiverBalance = initialReceiverBalance +
                transferAmount;

            // If transferFrom is used, make sure to properly approve the caller
            if (useTransferFrom) {
                vm.prank(account);

                autoPxGlp.approve(address(this), transferAmount);

                autoPxGlp.transferFrom(account, receiver, transferAmount);
            } else {
                vm.prank(account);

                autoPxGlp.transfer(receiver, transferAmount);
            }

            // Assert pxGMX reward states for both sender and receiver
            _assertUserRewardState(
                account,
                expectedLastUpdate,
                expectedSenderBalance,
                expectedSenderRewardState
            );
            _assertUserRewardState(
                receiver,
                expectedLastUpdate,
                expectedReceiverBalance,
                expectedReceiverRewardState
            );

            // Transfer should still update the balances and maintain totalSupply
            assertEq(supply, autoPxGlp.totalSupply());
            assertEq(expectedSenderBalance, autoPxGlp.balanceOf(account));
            assertEq(expectedReceiverBalance, autoPxGlp.balanceOf(receiver));
        }
    }
}
