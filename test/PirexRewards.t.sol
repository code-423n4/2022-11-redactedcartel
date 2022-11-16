// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {TransparentUpgradeableProxy} from "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {PirexRewards} from "src/PirexRewards.sol";
import {PirexRewardsMock} from "src/mocks/PirexRewardsMock.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {Helper} from "./Helper.sol";

contract PirexRewardsTest is Helper {
    /**
        @notice Perform assertions for global state
    */
    function _assertGlobalState(
        ERC20 producerToken,
        uint256 expectedLastUpdate,
        uint256 expectedLastSupply,
        uint256 expectedRewards
    ) internal {
        (
            uint256 lastUpdate,
            uint256 lastSupply,
            uint256 rewards
        ) = _getGlobalState(producerToken);

        assertEq(expectedLastUpdate, lastUpdate);
        assertEq(expectedLastSupply, lastSupply);
        assertEq(expectedRewards, rewards);
    }

    /*//////////////////////////////////////////////////////////////
                        setProducer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetProducerNotAuthorized() external {
        assertEq(address(pirexGmx), address(pirexRewards.producer()));

        address _producer = address(this);

        vm.prank(testAccounts[0]);
        vm.expectRevert(NOT_OWNER_ERROR);

        pirexRewards.setProducer(_producer);
    }

    /**
        @notice Test tx reversion: _producer is zero address
     */
    function testCannotSetProducerZeroAddress() external {
        assertEq(address(pirexGmx), address(pirexRewards.producer()));

        address invalidProducer = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setProducer(invalidProducer);
    }

    /**
        @notice Test tx success: set producer
     */
    function testSetProducer() external {
        assertEq(address(pirexGmx), address(pirexRewards.producer()));

        address producerBefore = address(pirexRewards.producer());
        address _producer = address(this);

        assertTrue(producerBefore != _producer);

        vm.expectEmit(false, false, false, true, address(pirexRewards));

        emit SetProducer(_producer);

        pirexRewards.setProducer(_producer);

        assertEq(_producer, address(pirexRewards.producer()));
    }

    /*//////////////////////////////////////////////////////////////
                        globalAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotGlobalAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.globalAccrue(invalidProducerToken);
    }

    /**
        @notice Test tx success: global rewards accrual for minting
        @param  secondsElapsed  uint32  Seconds to forward timestamp (affects rewards accrued)
        @param  mintAmount      uint96  Amount of pxGMX or pxGLP to mint
        @param  useGmx          bool    Whether to use pxGMX
     */
    function testGlobalAccrueMint(
        uint32 secondsElapsed,
        uint96 mintAmount,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(mintAmount != 0);
        vm.assume(mintAmount < 100000e18);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));
        (
            uint256 lastUpdateBeforeMint,
            uint256 lastSupplyBeforeMint,
            uint256 rewardsBeforeMint
        ) = _getGlobalState(producerToken);

        assertEq(0, lastUpdateBeforeMint);
        assertEq(0, lastSupplyBeforeMint);
        assertEq(0, rewardsBeforeMint);

        // Kick off global rewards accrual by minting first tokens
        _mintPx(address(this), mintAmount, useGmx);

        (
            uint256 lastUpdateAfterMint,
            uint256 lastSupplyAfterMint,
            uint256 rewardsAfterMint
        ) = _getGlobalState(producerToken);

        // Ensure that the update timestamp and supply are tracked
        assertEq(lastUpdateAfterMint, block.timestamp);
        assertEq(lastSupplyAfterMint, producerToken.totalSupply());

        // No rewards should have accrued since time has not elapsed
        assertEq(0, rewardsAfterMint);

        uint256 expectedTotalRewards = rewardsAfterMint;
        uint256 expectedLastUpdate = lastUpdateAfterMint;
        uint256 expectedTotalSupply = producerToken.totalSupply();

        // Perform minting to all test accounts and assert the updated global rewards accrual
        for (uint256 i; i < testAccounts.length; ++i) {
            // Forward timestamp to accrue rewards for each test accounts
            vm.warp(block.timestamp + secondsElapsed);

            // Total rewards should be what has been accrued based on the supply up to the last mint
            expectedTotalRewards += expectedTotalSupply * secondsElapsed;

            // Mint to call global reward accrual hook
            _mintPx(testAccounts[i], mintAmount, useGmx);

            expectedTotalSupply = producerToken.totalSupply();
            expectedLastUpdate += secondsElapsed;

            _assertGlobalState(
                producerToken,
                expectedLastUpdate,
                expectedTotalSupply,
                expectedTotalRewards
            );
        }
    }

    /**
        @notice Test tx success: global rewards accrual for burning
        @param  secondsElapsed  uint32  Seconds to forward timestamp (affects rewards accrued)
        @param  mintAmount      uint96  Amount of pxGLP to mint
        @param  burnPercent     uint8   Percent of pxGLP balance to burn
     */
    function testGlobalAccrueBurn(
        uint32 secondsElapsed,
        uint96 mintAmount,
        uint8 burnPercent
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(mintAmount > 1e18);
        vm.assume(mintAmount < 100000e18);
        vm.assume(burnPercent != 0);
        vm.assume(burnPercent <= 100);

        ERC20 producerToken = pxGlp;

        // Perform minting+burning to all test accounts and assert the updated global rewards accrual
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];

            _mintPx(testAccount, mintAmount, false);

            // Forward time in order to accrue rewards globally
            vm.warp(block.timestamp + secondsElapsed);

            uint256 preBurnSupply = pxGlp.totalSupply();
            uint256 burnAmount = (pxGlp.balanceOf(testAccount) * burnPercent) /
                100;

            // Global rewards accrued up to the last token burn
            uint256 expectedRewards = _calculateGlobalRewards(producerToken);

            _burnPxGlp(testAccount, burnAmount);

            (
                uint256 lastUpdate,
                uint256 lastSupply,
                uint256 rewards
            ) = _getGlobalState(producerToken);
            uint256 postBurnSupply = pxGlp.totalSupply();

            // Verify conditions for "less reward accrual" post-burn
            assertTrue(postBurnSupply < preBurnSupply);

            // Assert global rewards accrual post burn
            assertEq(expectedRewards, rewards);
            assertEq(block.timestamp, lastUpdate);
            assertEq(postBurnSupply, lastSupply);

            // Forward time in order to accrue rewards globally
            vm.warp(block.timestamp + secondsElapsed);

            // Global rewards accrued after the token burn
            uint256 expectedRewardsAfterBurn = _calculateGlobalRewards(
                producerToken
            );

            // Rewards accrued had supply not been reduced by burning
            uint256 noBurnRewards = rewards + preBurnSupply * secondsElapsed;

            // Delta of expected/actual rewards accrued and no-burn rewards accrued
            uint256 expectedAndNoBurnRewardDelta = (preBurnSupply -
                postBurnSupply) * secondsElapsed;

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit GlobalAccrue(
                producerToken,
                block.timestamp,
                postBurnSupply,
                expectedRewardsAfterBurn
            );

            pirexRewards.globalAccrue(producerToken);

            (, , uint256 rewardsAfterBurn) = _getGlobalState(producerToken);

            assertEq(expectedRewardsAfterBurn, rewardsAfterBurn);
            assertEq(
                expectedRewardsAfterBurn,
                noBurnRewards - expectedAndNoBurnRewardDelta
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        userAccrue TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotUserAccrueProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.userAccrue(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion: user is zero address
     */
    function testCannotUserAccrueUserZeroAddress() external {
        ERC20 producerToken = pxGlp;
        address invalidUser = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.userAccrue(producerToken, invalidUser);
    }

    /**
        @notice Test tx success: user rewards accrual
        @param  secondsElapsed    uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier        uint8   Multiplied with fixed token amounts for randomness
        @param  useETH            bool    Whether or not to use ETH as the source asset for minting GLP
        @param  testAccountIndex  uint8   Index of test account
        @param  useGmx            bool    Whether to use pxGMX
     */
    function testUserAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        uint8 testAccountIndex,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(testAccountIndex < 3);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

        address user = testAccounts[testAccountIndex];
        uint256 pxBalance = producerToken.balanceOf(user);
        (
            uint256 lastUpdateBefore,
            uint256 lastBalanceBefore,
            uint256 rewardsBefore
        ) = pirexRewards.getUserState(producerToken, user);
        uint256 warpTimestamp = block.timestamp + secondsElapsed;

        // GMX minting warps timestamp (timelock) so we will test for a non-zero value
        assertTrue(lastUpdateBefore != 0);

        // The recently minted balance amount should be what is stored in state
        assertEq(lastBalanceBefore, pxBalance);

        // User should not accrue rewards until time has passed
        assertEq(0, rewardsBefore);

        vm.warp(warpTimestamp);

        uint256 expectedUserRewards = _calculateUserRewards(
            producerToken,
            user
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UserAccrue(
            producerToken,
            user,
            block.timestamp,
            pxBalance,
            expectedUserRewards
        );

        pirexRewards.userAccrue(producerToken, user);

        (
            uint256 lastUpdateAfter,
            uint256 lastBalanceAfter,
            uint256 rewardsAfter
        ) = pirexRewards.getUserState(producerToken, user);

        assertEq(warpTimestamp, lastUpdateAfter);
        assertEq(pxBalance, lastBalanceAfter);
        assertEq(expectedUserRewards, rewardsAfter);
        assertTrue(rewardsAfter != 0);
    }

    /*//////////////////////////////////////////////////////////////
                globalAccrue/userAccrue integration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: minting px token and reward point accrual for multiple users
        @param  secondsElapsed  uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  useETH          bool    Whether or not to use ETH as the source asset for minting GLP
        @param  accrueGlobal    bool    Whether or not to update global reward accrual state
        @param  useGmx          bool    Whether to use pxGMX
     */
    function testAccrue(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        bool accrueGlobal,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

        // Forward timestamp by X seconds which will determine the total amount of rewards accrued
        vm.warp(block.timestamp + secondsElapsed);

        uint256 timestampBeforeAccrue = block.timestamp;
        uint256 expectedGlobalRewards = _calculateGlobalRewards(producerToken);

        if (accrueGlobal) {
            uint256 totalSupplyBeforeAccrue = producerToken.totalSupply();

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit GlobalAccrue(
                producerToken,
                timestampBeforeAccrue,
                totalSupplyBeforeAccrue,
                expectedGlobalRewards
            );

            pirexRewards.globalAccrue(producerToken);

            (
                uint256 lastUpdate,
                uint256 lastSupply,
                uint256 rewards
            ) = _getGlobalState(producerToken);

            assertEq(lastUpdate, timestampBeforeAccrue);
            assertEq(lastSupply, totalSupplyBeforeAccrue);
            assertEq(rewards, expectedGlobalRewards);
        }

        // The sum of all user rewards accrued for comparison against the expected global amount
        uint256 totalRewards;

        // Iterate over test accounts and check that reward accrual amount is correct for each one
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];
            uint256 balanceBeforeAccrue = producerToken.balanceOf(testAccount);
            uint256 expectedRewards = _calculateUserRewards(
                producerToken,
                testAccount
            );

            assertGt(expectedRewards, 0);

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit UserAccrue(
                producerToken,
                testAccount,
                block.timestamp,
                balanceBeforeAccrue,
                expectedRewards
            );

            pirexRewards.userAccrue(producerToken, testAccount);

            (
                uint256 lastUpdate,
                uint256 lastBalance,
                uint256 rewards
            ) = pirexRewards.getUserState(producerToken, testAccount);

            // Total rewards accrued by all users should add up to the global rewards
            totalRewards += rewards;

            assertEq(timestampBeforeAccrue, lastUpdate);
            assertEq(balanceBeforeAccrue, lastBalance);
            assertEq(expectedRewards, rewards);
        }

        assertEq(expectedGlobalRewards, totalRewards);
    }

    /**
        @notice Test tx success: minting px tokens and reward point accrual for multiple users with one who accrues asynchronously
        @param  secondsElapsed       uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  rounds               uint8   Number of rounds to fast forward time and accrue rewards
        @param  multiplier           uint8   Multiplied with fixed token amounts for randomness
        @param  useETH               bool    Whether or not to use ETH as the source asset for minting GLP
        @param  delayedAccountIndex  uint8   Test account index that will delay reward accrual until the end
        @param  useGmx               bool    Whether to use pxGMX
     */
    function testAccrueAsync(
        uint32 secondsElapsed,
        uint8 rounds,
        uint8 multiplier,
        bool useETH,
        uint8 delayedAccountIndex,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(rounds != 0);
        vm.assume(rounds < 10);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(delayedAccountIndex < 3);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

        // Sum up the rewards accrued - after all rounds - for accounts where accrual is not delayed
        uint256 nonDelayedTotalRewards;

        uint256 tLen = testAccounts.length;

        // Iterate over a number of rounds and accrue for non-delayed accounts
        for (uint256 i; i < rounds; ++i) {
            uint256 timestampBeforeAccrue = block.timestamp;

            // Forward timestamp by X seconds which will determine the total amount of rewards accrued
            vm.warp(timestampBeforeAccrue + secondsElapsed);

            for (uint256 j; j < tLen; ++j) {
                if (j != delayedAccountIndex) {
                    (, , uint256 rewardsBefore) = pirexRewards.getUserState(
                        producerToken,
                        testAccounts[j]
                    );
                    uint256 expectedUserRewards = _calculateUserRewards(
                        producerToken,
                        testAccounts[j]
                    );

                    vm.expectEmit(
                        true,
                        true,
                        false,
                        true,
                        address(pirexRewards)
                    );

                    emit UserAccrue(
                        producerToken,
                        testAccounts[j],
                        block.timestamp,
                        producerToken.balanceOf(testAccounts[j]),
                        expectedUserRewards
                    );

                    pirexRewards.userAccrue(producerToken, testAccounts[j]);

                    (, , uint256 rewardsAfter) = pirexRewards.getUserState(
                        producerToken,
                        testAccounts[j]
                    );

                    nonDelayedTotalRewards += rewardsAfter - rewardsBefore;

                    assertEq(expectedUserRewards, rewardsAfter);
                }
            }
        }

        // Calculate the rewards which should be accrued by the delayed account
        address delayedAccount = testAccounts[delayedAccountIndex];
        uint256 expectedDelayedRewards = _calculateUserRewards(
            producerToken,
            delayedAccount
        );
        uint256 expectedGlobalRewards = _calculateGlobalRewards(producerToken);

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UserAccrue(
            producerToken,
            delayedAccount,
            block.timestamp,
            producerToken.balanceOf(delayedAccount),
            expectedDelayedRewards
        );

        // Accrue rewards and check that the actual amount matches the expected
        pirexRewards.userAccrue(producerToken, delayedAccount);

        (, , uint256 rewardsAfterAccrue) = pirexRewards.getUserState(
            producerToken,
            delayedAccount
        );

        assertEq(expectedDelayedRewards, rewardsAfterAccrue);
        assertEq(
            expectedGlobalRewards,
            nonDelayedTotalRewards + rewardsAfterAccrue
        );
    }

    /**
        @notice Test tx success: assert correctness of reward accruals in the case of px token transfers
        @param  secondsElapsed   uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier       uint8   Multiplied with fixed token amounts for randomness
        @param  transferPercent  uint8   Percent for testing partial balance transfers
        @param  useTransfer      bool    Whether or not to use the transfer method
        @param  useETH           bool    Whether or not to use ETH as the source asset for minting GLP
        @param  useGmx           bool    Whether to use pxGMX
     */
    function testAccrueTransfer(
        uint32 secondsElapsed,
        uint8 multiplier,
        uint8 transferPercent,
        bool useTransfer,
        bool useETH,
        bool useGmx
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(transferPercent != 0);
        vm.assume(transferPercent <= 100);

        ERC20 producerToken = useGmx
            ? ERC20(address(pxGmx))
            : ERC20(address(pxGlp));

        _depositForTestAccounts(useGmx, multiplier, useETH);

        // Perform consecutive transfers in-between test accounts
        for (uint256 i; i < testAccounts.length; ++i) {
            address sender = testAccounts[i];
            // Transfer to next account, while last account would transfer to first account
            address receiver = testAccounts[(i + 1) % testAccounts.length];

            // Forward time in order to accrue rewards for sender
            vm.warp(block.timestamp + secondsElapsed);

            // Test sender reward accrual before transfer
            uint256 transferAmount = (producerToken.balanceOf(sender) *
                transferPercent) / 100;
            uint256 expectedSenderRewardsAfterTransfer = _calculateUserRewards(
                producerToken,
                sender
            );

            // Test both of the ERC20 transfer methods for correctness of reward accrual
            if (useTransfer) {
                vm.prank(sender);

                producerToken.transfer(receiver, transferAmount);
            } else {
                vm.prank(sender);

                // Need to increase allowance of the caller if using transferFrom
                producerToken.approve(address(this), transferAmount);

                producerToken.transferFrom(sender, receiver, transferAmount);
            }

            (, , uint256 senderRewardsAfterTransfer) = pirexRewards
                .getUserState(producerToken, sender);

            assertEq(
                expectedSenderRewardsAfterTransfer,
                senderRewardsAfterTransfer
            );

            // Forward time in order to accrue rewards for receiver
            vm.warp(block.timestamp + secondsElapsed);

            // Get expected sender and receiver reward accrual states
            uint256 expectedReceiverRewards = _calculateUserRewards(
                producerToken,
                receiver
            );
            uint256 expectedSenderRewardsAfterTransferAndWarp = _calculateUserRewards(
                    producerToken,
                    sender
                );

            // Accrue rewards for sender and receiver
            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit UserAccrue(
                producerToken,
                sender,
                block.timestamp,
                producerToken.balanceOf(sender),
                expectedSenderRewardsAfterTransferAndWarp
            );

            pirexRewards.userAccrue(producerToken, sender);

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit UserAccrue(
                producerToken,
                receiver,
                block.timestamp,
                producerToken.balanceOf(receiver),
                expectedReceiverRewards
            );

            pirexRewards.userAccrue(producerToken, receiver);

            // Retrieve actual user reward accrual states
            (, , uint256 receiverRewards) = pirexRewards.getUserState(
                producerToken,
                receiver
            );
            (, , uint256 senderRewardsAfterTransferAndWarp) = pirexRewards
                .getUserState(producerToken, sender);

            assertEq(
                expectedSenderRewardsAfterTransferAndWarp,
                senderRewardsAfterTransferAndWarp
            );
            assertEq(expectedReceiverRewards, receiverRewards);
        }
    }

    /**
        @notice Test tx success: assert correctness of reward accruals in the case of pxGLP burns
        @param  secondsElapsed   uint32  Seconds to forward timestamp (equivalent to total rewards accrued)
        @param  multiplier       uint8   Multiplied with fixed token amounts for randomness
        @param  burnPercent      uint8   Percent for testing partial balance burns
        @param  useETH           bool    Whether or not to use ETH as the source asset for minting GLP
     */
    function testAccrueBurn(
        uint32 secondsElapsed,
        uint8 multiplier,
        uint8 burnPercent,
        bool useETH
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(burnPercent != 0);
        vm.assume(burnPercent <= 100);

        // Always deposit for pxGLP for burn tests
        _depositForTestAccounts(false, multiplier, useETH);

        // Perform burn for all test accounts and assert global rewards accrual
        for (uint256 i; i < testAccounts.length; ++i) {
            address testAccount = testAccounts[i];

            // Forward time in order to accrue rewards for user
            vm.warp(block.timestamp + secondsElapsed);

            uint256 preBurnBalance = pxGlp.balanceOf(testAccount);
            uint256 burnAmount = (preBurnBalance * burnPercent) / 100;
            uint256 expectedRewardsAfterBurn = _calculateUserRewards(
                pxGlp,
                testAccount
            );

            vm.prank(address(pirexGmx));

            pxGlp.burn(testAccount, burnAmount);

            (
                uint256 updateAfterBurn,
                uint256 balanceAfterBurn,
                uint256 rewardsAfterBurn
            ) = pirexRewards.getUserState(pxGlp, testAccount);
            uint256 postBurnBalance = pxGlp.balanceOf(testAccount);

            // Verify conditions for "less reward accrual" post-burn
            assertTrue(postBurnBalance < preBurnBalance);

            // User should have accrued rewards based on their balance up to the burn
            // while still have the lastBalance state properly updated
            assertEq(expectedRewardsAfterBurn, rewardsAfterBurn);
            assertEq(postBurnBalance, balanceAfterBurn);
            assertEq(block.timestamp, updateAfterBurn);

            // Forward timestamp to check that user is accruing less rewards
            vm.warp(block.timestamp + secondsElapsed);

            uint256 expectedRewards = _calculateUserRewards(pxGlp, testAccount);

            // Rewards accrued if user were to not burn tokens
            uint256 noBurnRewards = rewardsAfterBurn +
                preBurnBalance *
                secondsElapsed;

            // Delta of expected/actual rewards accrued and no-burn rewards accrued
            uint256 expectedAndNoBurnRewardDelta = (preBurnBalance -
                postBurnBalance) * secondsElapsed;

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit UserAccrue(
                pxGlp,
                testAccount,
                block.timestamp,
                postBurnBalance,
                expectedRewards
            );

            pirexRewards.userAccrue(pxGlp, testAccount);

            (, , uint256 rewards) = pirexRewards.getUserState(
                pxGlp,
                testAccount
            );

            assertEq(expectedRewards, rewards);
            assertEq(noBurnRewards - expectedAndNoBurnRewardDelta, rewards);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            harvest TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: harvest WETH and esGMX rewards produced by pxGMX and pxGLP
        @param  secondsElapsed     uint32  Seconds to forward timestamp
        @param  rounds             uint8   Number of rounds to fast forward time and accrue rewards
        @param  multiplier         uint8   Multiplied with fixed token amounts for randomness
        @param  useETH             bool    Whether or not to use ETH as the source asset for minting GLP
        @param  additionalDeposit  uint8   Round index when another wave of deposit should be performed
     */
    function testHarvest(
        uint32 secondsElapsed,
        uint8 rounds,
        uint8 multiplier,
        bool useETH,
        uint8 additionalDeposit
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(rounds != 0);
        vm.assume(rounds < 10);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);
        vm.assume(additionalDeposit < rounds);

        // Perform initial pxGMX+pxGLP deposits for all test accounts before calling harvest
        _depositGmxForTestAccounts(true, address(this), multiplier);
        _depositGlpForTestAccounts(true, address(this), multiplier, useETH);

        ERC20[] memory expectedProducerTokens = new ERC20[](4);
        ERC20[] memory expectedRewardTokens = new ERC20[](4);
        uint256[] memory expectedRewardAmounts = new uint256[](4);
        uint256[] memory totalExpectedRewardAmounts = new uint256[](4);
        expectedProducerTokens[0] = pxGmx;
        expectedProducerTokens[1] = pxGlp;
        expectedProducerTokens[2] = pxGmx;
        expectedProducerTokens[3] = pxGlp;
        expectedRewardTokens[0] = weth;
        expectedRewardTokens[1] = weth;
        expectedRewardTokens[2] = ERC20(pxGmx); // esGMX rewards are distributed as pxGMX
        expectedRewardTokens[3] = ERC20(pxGmx);

        // Perform harvest for the specified amount of rounds (with delay) then asserts
        for (uint256 i; i < rounds; ++i) {
            // Perform additional deposits before the next harvest at randomly chosen index
            if (i == additionalDeposit) {
                _depositGmxForTestAccounts(true, address(this), multiplier);
                _depositGlpForTestAccounts(
                    true,
                    address(this),
                    multiplier,
                    useETH
                );
            }

            // Time skip to accrue rewards for each round
            vm.warp(block.timestamp + secondsElapsed);

            uint256 expectedLastUpdate = block.timestamp;
            uint256 expectedGlpGlobalLastSupply = pxGlp.totalSupply();
            uint256 expectedGlpGlobalRewards = _calculateGlobalRewards(pxGlp);
            uint256 expectedGmxGlobalLastSupply = pxGmx.totalSupply();
            uint256 expectedGmxGlobalRewards = _calculateGlobalRewards(pxGmx);
            expectedRewardAmounts[0] = _calculateRewards(
                address(pirexGmx),
                true,
                true
            );
            expectedRewardAmounts[1] = _calculateRewards(
                address(pirexGmx),
                true,
                false
            );
            expectedRewardAmounts[2] = _calculateRewards(
                address(pirexGmx),
                false,
                true
            );
            expectedRewardAmounts[3] = _calculateRewards(
                address(pirexGmx),
                false,
                false
            );

            vm.expectEmit(true, true, true, true, address(pirexRewards));

            emit Harvest(
                expectedProducerTokens,
                expectedRewardTokens,
                expectedRewardAmounts
            );

            (
                ERC20[] memory producerTokens,
                ERC20[] memory rewardTokens,
                uint256[] memory rewardAmounts
            ) = pirexRewards.harvest();

            // Asserts separately to avoid stack issues
            _assertGlobalState(
                pxGlp,
                expectedLastUpdate,
                expectedGlpGlobalLastSupply,
                expectedGlpGlobalRewards
            );
            _assertGlobalState(
                pxGmx,
                expectedLastUpdate,
                expectedGmxGlobalLastSupply,
                expectedGmxGlobalRewards
            );

            uint256 pLen = producerTokens.length;

            for (uint256 j; j < pLen; ++j) {
                ERC20 p = producerTokens[j];
                totalExpectedRewardAmounts[j] += rewardAmounts[j];

                assertEq(
                    totalExpectedRewardAmounts[j],
                    pirexRewards.getRewardState(p, rewardTokens[j])
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        setRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotSetRewardRecipientProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            invalidProducerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotSetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            producerToken,
            invalidRewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetRewardRecipientRecipientZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipient(
            producerToken,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test tx success: set reward recipient
     */
    function testSetRewardRecipient() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);
        address oldRecipient = pirexRewards.getRewardRecipient(
            address(this),
            producerToken,
            rewardToken
        );

        assertEq(address(0), oldRecipient);
        assertTrue(recipient != oldRecipient);

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipient(
            address(this),
            producerToken,
            rewardToken,
            recipient
        );

        pirexRewards.setRewardRecipient(producerToken, rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        unsetRewardRecipient TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotUnsetRewardRecipientProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotUnsetRewardRecipientRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipient(producerToken, invalidRewardToken);
    }

    /**
        @notice Test tx success: unset reward recipient
     */
    function testUnsetRewardRecipient() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );

        // Set reward recipient in order to unset
        pirexRewards.setRewardRecipient(pxGlp, rewardToken, recipient);

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit UnsetRewardRecipient(address(this), producerToken, rewardToken);

        pirexRewards.unsetRewardRecipient(producerToken, rewardToken);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                address(this),
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        addRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotAddRewardTokenNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        vm.expectRevert(NOT_OWNER_ERROR);

        vm.prank(testAccounts[0]);

        pirexRewards.addRewardToken(producerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotAddRewardTokenProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.addRewardToken(invalidProducerToken, rewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotAddRewardTokenRewardTokenZeroAddress() external {
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.addRewardToken(producerToken, invalidRewardToken);
    }

    /**
        @notice Test tx reversion: rewardToken is already added before
     */
    function testCannotAddRewardTokenAlreadyAdded() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        // Add a record before attempting to add the same token again
        pirexRewards.addRewardToken(producerToken, rewardToken);

        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );
        uint256 len = rewardTokensBeforePush.length;

        assertEq(1, len);

        // Attempt to add the same token
        vm.expectRevert(PirexRewards.TokenAlreadyAdded.selector);

        pirexRewards.addRewardToken(producerToken, rewardToken);
    }

    /**
        @notice Test tx success: add reward token
     */
    function testAddRewardToken() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(0, rewardTokensBeforePush.length);

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit AddRewardToken(producerToken, rewardToken);

        pirexRewards.addRewardToken(producerToken, rewardToken);

        ERC20[] memory rewardTokensAfterPush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(1, rewardTokensAfterPush.length);
        assertEq(address(rewardToken), address(rewardTokensAfterPush[0]));
    }

    /*//////////////////////////////////////////////////////////////
                        removeRewardToken TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotRemoveRewardTokenNotAuthorized() external {
        ERC20 producerToken = pxGlp;
        uint256 removalIndex = 0;

        vm.expectRevert(NOT_OWNER_ERROR);

        vm.prank(testAccounts[0]);

        pirexRewards.removeRewardToken(producerToken, removalIndex);
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotRemoveRewardTokenProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        uint256 removalIndex = 0;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.removeRewardToken(invalidProducerToken, removalIndex);
    }

    /**
        @notice Test tx reversion: invalid index (empty list)
     */
    function testCannotRemoveRewardTokenArithmeticError() external {
        ERC20 producerToken = pxGlp;
        uint256 invalidRemovalIndex = 1;

        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );
        uint256 len = rewardTokensBeforePush.length;

        assertEq(0, len);
        assertTrue(invalidRemovalIndex > len);

        vm.expectRevert(stdError.arithmeticError);

        pirexRewards.removeRewardToken(producerToken, invalidRemovalIndex);
    }

    /**
        @notice Test tx reversion: invalid index (index out of bounds on non empty list)
     */
    function testCannotRemoveRewardTokenIndexOutOfBounds() external {
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        uint256 invalidRemovalIndex = 2;

        // Add a record then attempt to remove using larger index
        pirexRewards.addRewardToken(producerToken, rewardToken);

        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );
        uint256 len = rewardTokensBeforePush.length;

        assertEq(1, len);
        assertTrue(invalidRemovalIndex > len);

        // Attemp to remove with invalid index (>= array size)
        vm.expectRevert(stdError.indexOOBError);

        pirexRewards.removeRewardToken(producerToken, invalidRemovalIndex);
    }

    /**
        @notice Test tx success: remove reward token at a random index
        @param  removalIndex  uint8  Index of the element to be removed
     */
    function testRemoveRewardToken(uint8 removalIndex) external {
        vm.assume(removalIndex < 2);

        ERC20 producerToken = pxGlp;
        address rewardToken1 = address(weth);
        address rewardToken2 = address(this);

        ERC20[] memory rewardTokensBeforePush = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(0, rewardTokensBeforePush.length);

        // Add rewardTokens to array to test proper removal
        pirexRewards.addRewardToken(producerToken, ERC20(rewardToken1));
        pirexRewards.addRewardToken(producerToken, ERC20(rewardToken2));

        ERC20[] memory rewardTokensBeforeRemoval = pirexRewards.getRewardTokens(
            producerToken
        );

        assertEq(2, rewardTokensBeforeRemoval.length);
        assertEq(rewardToken1, address(rewardTokensBeforeRemoval[0]));
        assertEq(rewardToken2, address(rewardTokensBeforeRemoval[1]));

        vm.expectEmit(true, false, false, true, address(pirexRewards));

        emit RemoveRewardToken(producerToken, removalIndex);

        pirexRewards.removeRewardToken(producerToken, removalIndex);

        ERC20[] memory rewardTokensAfterRemoval = pirexRewards.getRewardTokens(
            producerToken
        );
        address remainingToken = removalIndex == 0
            ? rewardToken2
            : rewardToken1;

        assertEq(1, rewardTokensAfterRemoval.length);
        assertEq(remainingToken, address(rewardTokensAfterRemoval[0]));
    }

    /*//////////////////////////////////////////////////////////////
                            claim TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotClaimProducerTokenZeroAddress() external {
        ERC20 invalidProducerToken = ERC20(address(0));
        address user = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.claim(invalidProducerToken, user);
    }

    /**
        @notice Test tx reversion: user is zero address
     */
    function testCannotClaimUserZeroAddress() external {
        ERC20 producerToken = pxGlp;
        address invalidUser = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.claim(producerToken, invalidUser);
    }

    /**
        @notice Test tx success: claim
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  useETH          bool    Whether to use ETH when minting
        @param  forwardRewards  bool    Whether to forward rewards
     */
    function testClaim(
        uint32 secondsElapsed,
        uint8 multiplier,
        bool useETH,
        bool forwardRewards
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _depositGmxForTestAccounts(true, address(this), multiplier);
        _depositGlpForTestAccounts(true, address(this), multiplier, useETH);

        vm.warp(block.timestamp + secondsElapsed);

        // Add reward token and harvest rewards from Pirex contract
        pirexRewards.addRewardToken(pxGmx, weth);
        pirexRewards.addRewardToken(pxGlp, weth);
        pirexRewards.harvest();

        for (uint256 i; i < testAccounts.length; ++i) {
            address recipient = forwardRewards
                ? address(this)
                : testAccounts[i];

            if (forwardRewards) {
                vm.startPrank(testAccounts[i]);

                pirexRewards.setRewardRecipient(pxGmx, weth, address(this));
                pirexRewards.setRewardRecipient(pxGlp, weth, address(this));

                vm.stopPrank();
            } else {
                assertEq(0, weth.balanceOf(testAccounts[i]));
            }

            pirexRewards.userAccrue(pxGmx, testAccounts[i]);
            pirexRewards.userAccrue(pxGlp, testAccounts[i]);

            (, , uint256 globalRewardsBeforeClaimPxGmx) = _getGlobalState(
                pxGmx
            );
            (, , uint256 globalRewardsBeforeClaimPxGlp) = _getGlobalState(
                pxGlp
            );
            (, , uint256 userRewardsBeforeClaimPxGmx) = pirexRewards
                .getUserState(pxGmx, testAccounts[i]);
            (, , uint256 userRewardsBeforeClaimPxGlp) = pirexRewards
                .getUserState(pxGlp, testAccounts[i]);

            // Sum of reward amounts that the user/recipient is entitled to
            uint256 expectedClaimAmount = ((pirexRewards.getRewardState(
                pxGmx,
                weth
            ) * _calculateUserRewards(pxGmx, testAccounts[i])) /
                _calculateGlobalRewards(pxGmx)) +
                ((pirexRewards.getRewardState(pxGlp, weth) *
                    _calculateUserRewards(pxGlp, testAccounts[i])) /
                    _calculateGlobalRewards(pxGlp));

            // Deduct previous balance if rewards are forwarded
            uint256 recipientBalanceDeduction = forwardRewards
                ? weth.balanceOf(recipient)
                : 0;

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit Claim(pxGmx, testAccounts[i]);

            pirexRewards.claim(pxGmx, testAccounts[i]);

            vm.expectEmit(true, true, false, true, address(pirexRewards));

            emit Claim(pxGlp, testAccounts[i]);

            pirexRewards.claim(pxGlp, testAccounts[i]);

            (, , uint256 globalRewardsAfterClaimPxGmx) = _getGlobalState(pxGmx);
            (, , uint256 globalRewardsAfterClaimPxGlp) = _getGlobalState(pxGlp);
            (, , uint256 userRewardsAfterClaimPxGmx) = pirexRewards
                .getUserState(pxGmx, testAccounts[i]);
            (, , uint256 userRewardsAfterClaimPxGlp) = pirexRewards
                .getUserState(pxGlp, testAccounts[i]);

            assertEq(
                globalRewardsBeforeClaimPxGmx - userRewardsBeforeClaimPxGmx,
                globalRewardsAfterClaimPxGmx
            );
            assertEq(
                globalRewardsBeforeClaimPxGlp - userRewardsBeforeClaimPxGlp,
                globalRewardsAfterClaimPxGlp
            );
            assertEq(0, userRewardsAfterClaimPxGmx);
            assertEq(0, userRewardsAfterClaimPxGlp);
            assertEq(
                expectedClaimAmount,
                weth.balanceOf(recipient) - recipientBalanceDeduction
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    setRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotSetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(NOT_OWNER_ERROR);

        vm.prank(testAccounts[0]);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotSetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        // Any address w/o code works (even non-EOA, contract addresses not on Arbi)
        address invalidLpContract = testAccounts[0];

        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken,
            recipient
        );

        // Covers zero addresses
        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.setRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotSetRewardRecipientPrivilegedProducerTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            invalidProducerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotSetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));
        address recipient = address(this);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            invalidRewardToken,
            recipient
        );
    }

    /**
        @notice Test tx reversion: recipient is zero address
     */
    function testCannotSetRewardRecipientPrivilegedRecipientZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address invalidRecipient = address(0);

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            invalidRecipient
        );
    }

    /**
        @notice Test tx success: set the reward recipient as the contract owner
     */
    function testSetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;
        address recipient = address(this);

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, true, true, address(pirexRewards));

        emit SetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                    unsetRewardRecipientPrivileged TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not authorized
     */
    function testCannotUnsetRewardRecipientPrivilegedNotAuthorized() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        vm.expectRevert(NOT_OWNER_ERROR);

        vm.prank(testAccounts[0]);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: lpContract is not a contract
     */
    function testCannotUnsetRewardRecipientPrivilegedLpContractNotContract()
        external
    {
        address invalidLpContract = testAccounts[0];
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken
        );

        invalidLpContract = address(0);

        vm.expectRevert(PirexRewards.NotContract.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            invalidLpContract,
            producerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: producerToken is zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedProducerTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 invalidProducerToken = ERC20(address(0));
        ERC20 rewardToken = weth;

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            invalidProducerToken,
            rewardToken
        );
    }

    /**
        @notice Test tx reversion: rewardToken is zero address
     */
    function testCannotUnsetRewardRecipientPrivilegedRewardTokenZeroAddress()
        external
    {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 invalidRewardToken = ERC20(address(0));

        vm.expectRevert(PirexRewards.ZeroAddress.selector);

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            invalidRewardToken
        );
    }

    /**
        @notice Test tx success: unset a reward recipient as the contract owner
     */
    function testUnsetRewardRecipientPrivileged() external {
        address lpContract = address(this);
        ERC20 producerToken = pxGlp;
        ERC20 rewardToken = weth;

        // Assert initial recipient
        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        // Set reward recipient in order to unset
        address recipient = address(this);

        pirexRewards.setRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );

        assertEq(
            recipient,
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );

        vm.expectEmit(true, true, false, true, address(pirexRewards));

        emit UnsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );

        pirexRewards.unsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );

        assertEq(
            address(0),
            pirexRewards.getRewardRecipient(
                lpContract,
                producerToken,
                rewardToken
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        upgrade TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx success: upgrade the PirexRewards contract
     */
    function testUpgrade() external {
        // Must be a payable-address due to the existence of fallback method on the base proxy
        address payable proxyAddress = payable(address(pirexRewards));
        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(
            proxyAddress
        );

        vm.prank(PROXY_ADMIN);

        // Store the old (pre-upgrade) implementation address before upgrading
        address oldImplementation = proxy.implementation();

        assertEq(proxyAddress, pirexGmx.pirexRewards());

        // Simulate deposit to accrue rewards in which the reward data
        // will be used later to test upgraded implementation
        address receiver = address(this);
        uint256 gmxAmount = 100e18;

        _mintApproveGmx(gmxAmount, address(this), address(pirexGmx), gmxAmount);
        pirexGmx.depositGmx(gmxAmount, receiver);

        vm.warp(block.timestamp + 1 days);

        pirexRewards.setProducer(address(pirexGmx));
        pirexRewards.harvest();

        uint256 oldMethodResult = pirexRewards.getRewardState(
            ERC20(address(pxGmx)),
            weth
        );

        assertGt(oldMethodResult, 0);

        // Deploy and set a new implementation to the proxy as the admin
        PirexRewardsMock newImplementation = new PirexRewardsMock();

        vm.startPrank(PROXY_ADMIN);

        proxy.upgradeTo(address(newImplementation));

        assertEq(address(newImplementation), proxy.implementation());
        assertTrue(oldImplementation != proxy.implementation());

        vm.stopPrank();

        // Confirm that the proxy implementation has been updated
        // by attempting to call a new method only available in the new instance
        // and also assert the returned value
        assertEq(
            oldMethodResult * 2,
            PirexRewardsMock(proxyAddress).getRewardStateMock(
                ERC20(address(pxGmx)),
                weth
            )
        );

        // Confirm that the address of the proxy doesn't change, only the implementation
        assertEq(proxyAddress, pirexGmx.pirexRewards());
    }
}
