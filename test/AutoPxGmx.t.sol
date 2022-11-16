// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {AutoPxGmx} from "src/vaults/AutoPxGmx.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {Helper} from "./Helper.sol";

contract AutoPxGmxTest is Helper {
    event PoolFeeUpdated(uint24 _poolFee);
    event Compounded(
        address indexed caller,
        uint24 fee,
        uint256 amountOutMinimum,
        uint160 sqrtPriceLimitX96,
        uint256 wethAmountIn,
        uint256 gmxAmountOut,
        uint256 pxGmxMintAmount,
        uint256 totalFee,
        uint256 incentive
    );
    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /**
        @notice Provision reward state to test compounding of rewards
        @param  assets            uint256    GMX/pxGMX amount to deposit in the vault
        @param  receivers         address[]  Receivers of the apxGMX tokens
        @param  secondsElapsed    uint256    Seconds to forward timestamp
        @return wethRewardState   uint256    WETH reward state
        @return pxGmxRewardState  uint256    pxGMX reward state
        @return shareBalances     uint256[]  Receivers' apxGMX balances
     */
    function _provisionRewardState(
        uint256 assets,
        address[] memory receivers,
        uint256 secondsElapsed
    )
        internal
        returns (
            uint256 wethRewardState,
            uint256 pxGmxRewardState,
            uint256[] memory shareBalances
        )
    {
        uint256 rLen = receivers.length;
        shareBalances = new uint256[](rLen);

        for (uint256 i; i < rLen; ++i) {
            address receiver = receivers[i];

            _depositGmx(assets, receiver);

            vm.startPrank(receiver);

            pxGmx.approve(address(autoPxGmx), assets);

            shareBalances[i] = autoPxGmx.deposit(assets, receiver);

            vm.stopPrank();
        }

        vm.warp(block.timestamp + secondsElapsed);

        pirexRewards.addRewardToken(pxGmx, weth);
        pirexRewards.addRewardToken(pxGmx, pxGmx);
        pirexRewards.harvest();

        wethRewardState = pirexRewards.getRewardState(pxGmx, weth);
        pxGmxRewardState = pirexRewards.getRewardState(pxGmx, pxGmx);
    }

    /*//////////////////////////////////////////////////////////////
                        setPoolFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPoolFeeUnauthorized() external {
        uint24 fee = 1;

        vm.expectRevert("UNAUTHORIZED");

        vm.prank(testAccounts[0]);

        autoPxGmx.setPoolFee(fee);
    }

    /**
        @notice Test tx reversion: pool fee is zero
     */
    function testCannotSetPoolFeeZeroAmount() external {
        uint24 invalidFee = 0;

        vm.expectRevert(AutoPxGmx.ZeroAmount.selector);

        autoPxGmx.setPoolFee(invalidFee);
    }

    /**
        @notice Test tx success: set pool fee
     */
    function testSetPoolFee() external {
        uint24 initialPoolFee = autoPxGmx.poolFee();
        uint24 fee = 10000;
        uint24 expectedPoolFee = fee;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit PoolFeeUpdated(expectedPoolFee);

        autoPxGmx.setPoolFee(fee);

        assertEq(expectedPoolFee, autoPxGmx.poolFee());
        assertTrue(expectedPoolFee != initialPoolFee);
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

        autoPxGmx.setWithdrawalPenalty(penalty);
    }

    /**
        @notice Test tx reversion: penalty exceeds max
     */
    function testCannotSetWithdrawalPenaltyExceedsMax() external {
        uint256 invalidPenalty = autoPxGmx.MAX_WITHDRAWAL_PENALTY() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setWithdrawalPenalty(invalidPenalty);
    }

    /**
        @notice Test tx success: set withdrawal penalty
     */
    function testSetWithdrawalPenalty() external {
        uint256 initialWithdrawalPenalty = autoPxGmx.withdrawalPenalty();
        uint256 penalty = 1;
        uint256 expectedWithdrawalPenalty = penalty;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit WithdrawalPenaltyUpdated(expectedWithdrawalPenalty);

        autoPxGmx.setWithdrawalPenalty(penalty);

        assertEq(expectedWithdrawalPenalty, autoPxGmx.withdrawalPenalty());
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

        autoPxGmx.setPlatformFee(fee);
    }

    /**
        @notice Test tx reversion: fee exceeds max
     */
    function testCannotSetPlatformFeeExceedsMax() external {
        uint256 invalidFee = autoPxGmx.MAX_PLATFORM_FEE() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setPlatformFee(invalidFee);
    }

    /**
        @notice Test tx success: set platform fee
     */
    function testSetPlatformFee() external {
        uint256 initialPlatformFee = autoPxGmx.platformFee();
        uint256 fee = 1;
        uint256 expectedPlatformFee = fee;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit PlatformFeeUpdated(expectedPlatformFee);

        autoPxGmx.setPlatformFee(fee);

        assertEq(expectedPlatformFee, autoPxGmx.platformFee());
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

        autoPxGmx.setCompoundIncentive(incentive);
    }

    /**
        @notice Test tx reversion: incentive exceeds max
     */
    function testCannotSetCompoundIncentiveExceedsMax() external {
        uint256 invalidIncentive = autoPxGmx.MAX_COMPOUND_INCENTIVE() + 1;

        vm.expectRevert(AutoPxGmx.ExceedsMax.selector);

        autoPxGmx.setCompoundIncentive(invalidIncentive);
    }

    /**
        @notice Test tx success: set compound incentive percent
     */
    function testSetCompoundIncentive() external {
        uint256 initialCompoundIncentive = autoPxGmx.compoundIncentive();
        uint256 incentive = 1;
        uint256 expectedCompoundIncentive = incentive;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit CompoundIncentiveUpdated(expectedCompoundIncentive);

        autoPxGmx.setCompoundIncentive(incentive);

        assertEq(expectedCompoundIncentive, autoPxGmx.compoundIncentive());
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

        autoPxGmx.setPlatform(platform);
    }

    /**
        @notice Test tx reversion: platform is zero address
     */
    function testCannotSetPlatformZeroAddress() external {
        address invalidPlatform = address(0);

        vm.expectRevert(AutoPxGmx.ZeroAddress.selector);

        autoPxGmx.setPlatform(invalidPlatform);
    }

    /**
        @notice Test tx success: set platform
     */
    function testSetPlatform() external {
        address initialPlatform = autoPxGmx.platform();
        address platform = address(this);
        address expectedPlatform = platform;

        vm.expectEmit(false, false, false, true, address(autoPxGmx));

        emit PlatformUpdated(expectedPlatform);

        autoPxGmx.setPlatform(platform);

        assertEq(expectedPlatform, autoPxGmx.platform());
        assertTrue(expectedPlatform != initialPlatform);
    }

    /*//////////////////////////////////////////////////////////////
                        totalAssets TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice  Test tx success: return the total assets
    */
    function testTotalAssets() external {
        uint256 initialTotalAssets = autoPxGmx.totalAssets();
        uint256 assets = 1;
        address receiver = address(this);
        uint256 expectedTotalAssets = assets;

        _depositGmx(assets, receiver);
        pxGmx.approve(address(autoPxGmx), assets);
        autoPxGmx.deposit(assets, receiver);

        assertEq(expectedTotalAssets, autoPxGmx.totalAssets());
        assertTrue(expectedTotalAssets != initialTotalAssets);
    }

    /*//////////////////////////////////////////////////////////////
                        compound TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: fee is invalid param
     */
    function testCannotCompoundFeeInvalidParam() external {
        uint24 invalidFee = 0;
        uint256 amountOutMinimum = 1;
        uint160 sqrtPriceLimitX96 = 1;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(
            invalidFee,
            amountOutMinimum,
            sqrtPriceLimitX96,
            optOutIncentive
        );
    }

    /**
        @notice Test tx reversion: amountOutMinimum is invalid param
     */
    function testCannotCompoundAmountOutMinimumInvalidParam() external {
        uint24 fee = 3000;
        uint256 invalidAmountOutMinimum = 0;
        uint160 sqrtPriceLimitX96 = 1;
        bool optOutIncentive = true;

        vm.expectRevert(AutoPxGmx.InvalidParam.selector);

        autoPxGmx.compound(
            fee,
            invalidAmountOutMinimum,
            sqrtPriceLimitX96,
            optOutIncentive
        );
    }

    /**
        @notice Test tx success: compound pxGMX rewards into more pxGMX
        @param  gmxAmount       uint96  Amount of pxGMX to get from the deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testCompound(uint96 gmxAmount, uint32 secondsElapsed) external {
        vm.assume(gmxAmount > 5e17);
        vm.assume(gmxAmount < 100000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        address[] memory receivers = new address[](1);
        receivers[0] = address(this);
        (
            uint256 wethRewardState,
            uint256 pxGmxRewardState,

        ) = _provisionRewardState(gmxAmount, receivers, secondsElapsed);
        uint256 totalAssetsBeforeCompound = autoPxGmx.totalAssets();
        uint256 shareToAssetAmountBeforeCompound = autoPxGmx.convertToAssets(
            autoPxGmx.balanceOf(address(this))
        );

        // Confirm current state prior to primary state mutating action
        assertEq(gmxAmount, autoPxGmx.balanceOf(address(this)));
        assertEq(gmxAmount, totalAssetsBeforeCompound);
        assertGt(wethRewardState, 0);
        assertGt(pxGmxRewardState, 0);
        assertEq(0, pxGmx.balanceOf(autoPxGmx.owner()));

        vm.expectEmit(true, false, false, false, address(autoPxGmx));

        emit Compounded(testAccounts[0], 3000, 1, 0, 0, 0, 0, 0, 0);

        // Call as testAccounts[0] to test compound incentive transfer
        vm.prank(testAccounts[0]);

        // Input literal argument values due to callstack depth error
        (
            uint256 wethAmountIn,
            uint256 gmxAmountOut,
            uint256 pxGmxMintAmount,
            uint256 totalFee,
            uint256 incentive
        ) = autoPxGmx.compound(3000, 1, 0, false);

        uint256 expectedTotalFee = ((pxGmxMintAmount + pxGmxRewardState) *
            autoPxGmx.platformFee()) / autoPxGmx.FEE_DENOMINATOR();
        uint256 expectedCompoundIncentive = (totalFee *
            autoPxGmx.compoundIncentive()) / autoPxGmx.FEE_DENOMINATOR();
        uint256 expectedPlatformFee = expectedTotalFee -
            expectedCompoundIncentive;
        uint256 expectedTotalAssets = totalAssetsBeforeCompound +
            pxGmxMintAmount +
            pxGmxRewardState -
            expectedTotalFee;
        uint256 expectedShareToAssetAmountDifference = ((autoPxGmx.balanceOf(
            address(this)
        ) * expectedTotalAssets) / autoPxGmx.totalSupply()) -
            shareToAssetAmountBeforeCompound;

        assertEq(wethRewardState, wethAmountIn);

        // // This will not always be the case in production (external party transfers GMX to vault)
        // // But for this test, this assertion should hold true
        assertEq(gmxAmountOut, pxGmxMintAmount);

        assertEq(
            gmxAmountOut + pxGmxRewardState - expectedTotalFee,
            autoPxGmx.totalAssets() - totalAssetsBeforeCompound
        );
        assertEq(
            pxGmxMintAmount + pxGmxRewardState - expectedTotalFee,
            autoPxGmx.totalAssets() - totalAssetsBeforeCompound
        );
        assertGt(expectedTotalAssets, totalAssetsBeforeCompound);
        assertEq(expectedTotalAssets, autoPxGmx.totalAssets());
        assertEq(
            expectedShareToAssetAmountDifference,
            autoPxGmx.convertToAssets(autoPxGmx.balanceOf(address(this))) -
                shareToAssetAmountBeforeCompound
        );
        assertEq(expectedTotalFee, totalFee);
        assertEq(expectedCompoundIncentive, incentive);
        assertEq(expectedPlatformFee + expectedCompoundIncentive, totalFee);
        assertEq(expectedPlatformFee, pxGmx.balanceOf(autoPxGmx.owner()));
        assertEq(expectedCompoundIncentive, pxGmx.balanceOf(testAccounts[0]));
        assertLt(
            shareToAssetAmountBeforeCompound,
            autoPxGmx.convertToAssets(autoPxGmx.balanceOf(address(this)))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        withdraw TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: withdraw from vault and assert the withdrawn assets
        @param  gmxAmount       uint96  Amount of pxGMX to get from the deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testWithdraw(uint96 gmxAmount, uint32 secondsElapsed) external {
        vm.assume(gmxAmount > 5e17);
        vm.assume(gmxAmount < 100000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        address[] memory receivers = new address[](testAccounts.length);
        uint256[] memory assetBalances = new uint256[](testAccounts.length);
        for (uint256 i; i < testAccounts.length; ++i) {
            receivers[i] = testAccounts[i];
        }

        (, , uint256[] memory shareBalances) = _provisionRewardState(
            gmxAmount,
            receivers,
            secondsElapsed
        );

        // Store current redemption values before the first compound trigger
        for (uint256 i; i < testAccounts.length; ++i) {
            assetBalances[i] = autoPxGmx.previewRedeem(shareBalances[i]);
        }

        for (uint256 i; i < testAccounts.length; ++i) {
            uint256 initialShare = autoPxGmx.balanceOf(testAccounts[i]);

            assertEq(shareBalances[i], initialShare);

            uint256 initialSupply = autoPxGmx.totalSupply();

            // Withdraw from the vault and assert the updated assets
            vm.prank(testAccounts[i]);

            // Attempt to withdraw using previous asset snapshot before compound,
            // which means the user might still have some leftover of the share due to the compound call
            autoPxGmx.withdraw(
                assetBalances[i],
                testAccounts[i],
                testAccounts[i]
            );

            // Withdrawal should still decrement the totalSupply and user shares
            // Using approximation since we can't get exact amount of new GMX from the compound trigger
            // before triggering it via the withdraw call
            assertLe(initialSupply - initialShare, autoPxGmx.totalSupply());
            assertGe(autoPxGmx.balanceOf(testAccounts[i]), 0);

            // Since we use withdraw, the actual received pxGmx should be equal to the
            // previously stored redeem preview balance
            assertEq(pxGmx.balanceOf(testAccounts[i]), assetBalances[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        redeem TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: redeem from vault and assert the redeemed assets
        @param  gmxAmount       uint96  Amount of pxGMX to get from the deposit
        @param  secondsElapsed  uint32  Seconds to forward timestamp
     */
    function testRedeem(uint96 gmxAmount, uint32 secondsElapsed) external {
        vm.assume(gmxAmount > 5e17);
        vm.assume(gmxAmount < 100000e18);
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);

        address[] memory receivers = new address[](testAccounts.length);
        uint256[] memory assetBalances = new uint256[](testAccounts.length);
        for (uint256 i; i < testAccounts.length; ++i) {
            receivers[i] = testAccounts[i];
        }

        (, , uint256[] memory shareBalances) = _provisionRewardState(
            gmxAmount,
            receivers,
            secondsElapsed
        );

        // Store current redemption values before the first compound trigger
        for (uint256 i; i < testAccounts.length; ++i) {
            assetBalances[i] = autoPxGmx.previewRedeem(shareBalances[i]);
        }

        for (uint256 i; i < testAccounts.length; ++i) {
            uint256 initialShare = autoPxGmx.balanceOf(testAccounts[i]);

            assertEq(shareBalances[i], initialShare);

            uint256 initialSupply = autoPxGmx.totalSupply();

            // Redeem from the vault and assert the updated assets
            vm.prank(testAccounts[i]);

            autoPxGmx.redeem(initialShare, testAccounts[i], testAccounts[i]);

            // Redemption should still decrement the totalSupply and user shares
            assertEq(initialSupply - initialShare, autoPxGmx.totalSupply());
            assertEq(0, autoPxGmx.balanceOf(testAccounts[i]));

            // Also check the actual redeemed pxGMX amount compared to the preview before the first compound
            assertGt(pxGmx.balanceOf(testAccounts[i]), assetBalances[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        depositGmx TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotDepositGmxAmountZeroAmount() external {
        uint256 invalidAmount = 0;
        address receiver = address(this);

        vm.expectRevert(AutoPxGmx.ZeroAmount.selector);

        autoPxGmx.depositGmx(invalidAmount, receiver);
    }

    /**
        @notice Test tx reversion: receiver is the zero address
     */
    function testCannotDepositGmxReceiverZeroAddress() external {
        uint256 amount = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(AutoPxGmx.ZeroAddress.selector);

        autoPxGmx.depositGmx(amount, invalidReceiver);
    }

    /**
        @notice Test tx success: deposit GMX for apxGMX
     */
    function testDepositGmx() external {
        uint256 amount = 1e18;
        address receiver = address(this);
        uint256 depositFee = 10000;

        pirexGmx.setFee(PirexGmx.Fees.Deposit, depositFee);

        (uint256 expectedAssets, ) = _computeAssetAmounts(
            PirexGmx.Fees.Deposit,
            amount
        );
        uint256 expectedShares = autoPxGmx.previewDeposit(expectedAssets);

        _mintApproveGmx(amount, address(this), address(autoPxGmx), amount);

        assertTrue(amount == gmx.balanceOf(address(this)));
        assertTrue(0 == autoPxGmx.totalAssets());
        assertTrue(0 == autoPxGmx.totalSupply());

        vm.expectEmit(true, true, false, false, address(autoPxGmx));

        emit Deposit(receiver, receiver, expectedAssets, expectedShares);

        autoPxGmx.depositGmx(amount, receiver);

        assertTrue(0 == gmx.balanceOf(address(this)));
        assertTrue(expectedAssets == autoPxGmx.totalAssets());
        assertTrue(expectedShares == autoPxGmx.totalSupply());
    }

    /**
        @notice Test tx success: deposit GMX for apxGMX (fuzz)
     */
    function testDepositGmxFuzz(
        uint80 amount,
        uint24 depositFee,
        bool separateCaller,
        uint8 multiplier
    ) external {
        vm.assume(amount > 1e15);
        vm.assume(amount < 10000e18);
        vm.assume(depositFee != 0);
        vm.assume(depositFee <= feeMax);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        pirexGmx.setFee(PirexGmx.Fees.Deposit, depositFee);

        uint256 expectedTotalAssets;
        uint256 expectedTotalSupply;

        for (uint256 i; i < testAccounts.length; ++i) {
            address receiver = testAccounts[i];
            address caller = separateCaller ? address(this) : receiver;
            uint256 amountWithMultiplier = uint256(amount) *
                uint256(multiplier);
            (uint256 expectedAssets, ) = _computeAssetAmounts(
                PirexGmx.Fees.Deposit,
                amountWithMultiplier
            );
            uint256 expectedShares = autoPxGmx.previewDeposit(expectedAssets);

            expectedTotalAssets += expectedAssets;
            expectedTotalSupply += expectedShares;

            _mintApproveGmx(
                amountWithMultiplier,
                caller,
                address(autoPxGmx),
                amountWithMultiplier
            );

            vm.prank(caller);
            vm.expectEmit(true, true, false, false, address(autoPxGmx));

            emit Deposit(caller, receiver, expectedAssets, expectedShares);

            autoPxGmx.depositGmx(amountWithMultiplier, receiver);

            assertTrue(expectedShares == autoPxGmx.balanceOf(receiver));
            assertTrue(expectedTotalAssets == autoPxGmx.totalAssets());
            assertTrue(expectedTotalSupply == autoPxGmx.totalSupply());
        }
    }
}
