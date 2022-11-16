// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {IWETH} from "src/interfaces/IWETH.sol";
import {DelegateRegistry} from "src/external/DelegateRegistry.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {IGlpManager} from "src/interfaces/IGlpManager.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {Helper} from "./Helper.sol";

contract PirexGmxTest is Test, Helper {
    bytes internal constant PAUSED_ERROR = "Pausable: paused";
    bytes internal constant NOT_PAUSED_ERROR = "Pausable: not paused";
    bytes internal constant INSUFFICIENT_OUTPUT_ERROR =
        "GlpManager: insufficient output";
    bytes internal constant INSUFFICIENT_GLP_OUTPUT_ERROR =
        "GlpManager: insufficient GLP output";

    /**
        @notice Get an address that is unauthorized (i.e. not owner)
        @return unauthorizedCaller  address  Unauthorized caller
     */
    function _getUnauthorizedCaller()
        internal
        returns (address unauthorizedCaller)
    {
        unauthorizedCaller = testAccounts[0];

        assertTrue(unauthorizedCaller != pirexGmx.owner());
    }

    /**
        @notice Pause and verify pause state for contract
     */
    function _pauseContract() internal {
        pirexGmx.setPauseState(true);

        assertEq(true, pirexGmx.paused());
    }

    /**
        @notice Set fee, verify event emission, and validate new state
        @param  f    enum     Fee type
        @param  fee  uint256  Fee
     */
    function _setFee(PirexGmx.Fees f, uint256 fee) internal {
        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetFee(f, fee);

        pirexGmx.setFee(f, fee);

        assertEq(fee, pirexGmx.fees(f));
    }

    /**
        @notice Set contract, verify event emission, and validate new state
        @param  c                enum     Contract type
        @param  contractAddress  address  Contract address
     */
    function _setContract(PirexGmx.Contracts c, address contractAddress)
        internal
    {
        vm.expectEmit(true, false, false, true, address(pirexGmx));

        emit SetContract(c, contractAddress);

        pirexGmx.setContract(c, contractAddress);

        address newContractAddress;

        // Use a conditional statement to set newContractAddress since no getter
        if (c == PirexGmx.Contracts.PirexFees)
            newContractAddress = address(pirexGmx.pirexFees());
        if (c == PirexGmx.Contracts.RewardRouterV2)
            newContractAddress = address(pirexGmx.gmxRewardRouterV2());
        if (c == PirexGmx.Contracts.RewardTrackerGmx)
            newContractAddress = address(pirexGmx.rewardTrackerGmx());
        if (c == PirexGmx.Contracts.RewardTrackerGlp)
            newContractAddress = address(pirexGmx.rewardTrackerGlp());
        if (c == PirexGmx.Contracts.FeeStakedGlp)
            newContractAddress = address(pirexGmx.feeStakedGlp());
        if (c == PirexGmx.Contracts.StakedGmx)
            newContractAddress = address(pirexGmx.stakedGmx());
        if (c == PirexGmx.Contracts.StakedGlp)
            newContractAddress = address(pirexGmx.stakedGlp());
        if (c == PirexGmx.Contracts.GmxVault)
            newContractAddress = address(pirexGmx.gmxVault());
        if (c == PirexGmx.Contracts.GlpManager)
            newContractAddress = address(pirexGmx.glpManager());

        assertEq(contractAddress, newContractAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            configureGmxState TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotConfigureGmxStateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.configureGmxState();
    }

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotConfigureGmxStateNotPaused() external {
        assertEq(false, pirexGmx.paused());

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.configureGmxState();
    }

    /**
        @notice Test tx success: configure GMX state
     */
    function testConfigureGmxState() external {
        PirexGmx freshPirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry),
            // The `weth` variable is used on both Ethereum and Avalanche for the base rewards
            REWARD_ROUTER_V2.weth(),
            REWARD_ROUTER_V2.gmx(),
            REWARD_ROUTER_V2.esGmx(),
            address(REWARD_ROUTER_V2),
            address(STAKED_GLP)
        );

        assertEq(address(this), freshPirexGmx.owner());
        assertEq(true, freshPirexGmx.paused());
        assertEq(address(0), address(freshPirexGmx.rewardTrackerGmx()));
        assertEq(address(0), address(freshPirexGmx.rewardTrackerGlp()));
        assertEq(address(0), address(freshPirexGmx.feeStakedGlp()));
        assertEq(address(0), address(freshPirexGmx.stakedGmx()));
        assertEq(address(0), address(freshPirexGmx.glpManager()));
        assertEq(address(0), address(freshPirexGmx.gmxVault()));
        assertEq(0, gmx.allowance(address(freshPirexGmx), address(stakedGmx)));

        IVault gmxVault = IVault(IGlpManager(glpManager).vault());

        vm.expectEmit(true, false, false, true, address(freshPirexGmx));

        emit ConfigureGmxState(
            address(this),
            rewardTrackerGmx,
            rewardTrackerGlp,
            feeStakedGlp,
            stakedGmx,
            address(glpManager),
            gmxVault
        );

        freshPirexGmx.configureGmxState();

        assertEq(
            address(rewardTrackerGmx),
            address(freshPirexGmx.rewardTrackerGmx())
        );
        assertEq(
            address(rewardTrackerGlp),
            address(freshPirexGmx.rewardTrackerGlp())
        );
        assertEq(address(feeStakedGlp), address(freshPirexGmx.feeStakedGlp()));
        assertEq(address(stakedGmx), address(freshPirexGmx.stakedGmx()));
        assertEq(address(glpManager), address(freshPirexGmx.glpManager()));
        assertEq(address(gmxVault), address(freshPirexGmx.gmxVault()));
        assertEq(type(uint256).max, gmx.allowance(address(freshPirexGmx), address(stakedGmx)));
    }

    /*//////////////////////////////////////////////////////////////
                            setFee TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetFeeUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();
        uint256 fee = 1;

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setFee(PirexGmx.Fees.Deposit, fee);
    }

    /**
        @notice Test tx reversion: fee is invalid
     */
    function testCannotSetFeeInvalidFee() external {
        uint256 invalidFee = feeMax + 1;

        for (uint256 i; i < feeTypes.length; ++i) {
            vm.expectRevert(PirexGmx.InvalidFee.selector);

            pirexGmx.setFee(feeTypes[i], invalidFee);
        }
    }

    /**
        @notice Test tx success: set fees for each type
        @param  depositFee     uint24  Deposit fee
        @param  redemptionFee  uint24  Redemption fee
        @param  rewardFee      uint24  Reward fee
     */
    function testSetFee(
        uint24 depositFee,
        uint24 redemptionFee,
        uint24 rewardFee
    ) external {
        vm.assume(depositFee != 0);
        vm.assume(depositFee <= feeMax);
        vm.assume(redemptionFee != 0);
        vm.assume(redemptionFee < feeMax);
        vm.assume(rewardFee != 0);
        vm.assume(rewardFee < feeMax);

        PirexGmx.Fees depositFeeType = feeTypes[0];
        PirexGmx.Fees redemptionFeeType = feeTypes[1];
        PirexGmx.Fees rewardFeeType = feeTypes[2];

        assertEq(0, pirexGmx.fees(depositFeeType));
        assertEq(0, pirexGmx.fees(redemptionFeeType));
        assertEq(0, pirexGmx.fees(rewardFeeType));

        // Set and validate the different fee types
        _setFee(depositFeeType, depositFee);
        _setFee(redemptionFeeType, redemptionFee);
        _setFee(rewardFeeType, rewardFee);
    }

    /*//////////////////////////////////////////////////////////////
                        setContract TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetContractNotAuthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();
        address contractAddress = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardRouterV2,
            contractAddress
        );
    }

    /**
        @notice Test tx reversion: contractAddress is the zero address
     */
    function testCannotSetContractZeroAddress() external {
        address invalidContractAddress = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.setContract(
            PirexGmx.Contracts.RewardRouterV2,
            invalidContractAddress
        );
    }

    /**
        @notice Test tx success: set pirexFees to a new contract address
     */
    function testSetContractPirexFees() external {
        address currentContractAddress = address(pirexGmx.pirexFees());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.PirexFees, contractAddress);
    }

    /**
        @notice Test tx success: set gmxRewardRouterV2 to a new contract address
     */
    function testSetContractRewardRouterV2() external {
        address currentContractAddress = address(pirexGmx.gmxRewardRouterV2());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.RewardRouterV2, contractAddress);
    }

    /**
        @notice Test tx success: set rewardTrackerGmx to a new contract address
     */
    function testSetContractRewardTrackerGmx() external {
        address currentContractAddress = address(pirexGmx.rewardTrackerGmx());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.RewardTrackerGmx, contractAddress);
    }

    /**
        @notice Test tx success: set rewardTrackerGlp to a new contract address
     */
    function testSetContractRewardTrackerGlp() external {
        address currentContractAddress = address(pirexGmx.rewardTrackerGlp());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.RewardTrackerGlp, contractAddress);
    }

    /**
        @notice Test tx success: set feeStakedGlp to a new contract address
     */
    function testSetContractFeeStakedGlp() external {
        address currentContractAddress = address(pirexGmx.feeStakedGlp());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.FeeStakedGlp, contractAddress);
    }

    /**
        @notice Test tx success: set stakedGmx to a new contract address
     */
    function testSetContractStakedGmx() external {
        address currentContractAddress = address(pirexGmx.stakedGmx());
        uint256 currentContractAddressAllowance = type(uint256).max;
        address contractAddress = address(this);

        assertFalse(contractAddress == currentContractAddress);
        assertEq(
            currentContractAddressAllowance,
            gmx.allowance(address(pirexGmx), currentContractAddress)
        );

        uint256 expectedCurrentContractAllowance = 0;
        uint256 expectedContractAddressAllowance = type(uint256).max;

        assertFalse(
            currentContractAddressAllowance == expectedCurrentContractAllowance
        );

        _setContract(PirexGmx.Contracts.StakedGmx, contractAddress);

        assertEq(
            expectedCurrentContractAllowance,
            gmx.allowance(address(pirexGmx), currentContractAddress)
        );
        assertEq(
            expectedContractAddressAllowance,
            gmx.allowance(address(pirexGmx), contractAddress)
        );
    }

    /**
        @notice Test tx success: set feeStakedGlp to a new contract address
     */
    function testSetContractStakedGlp() external {
        address currentContractAddress = address(pirexGmx.stakedGlp());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.StakedGlp, contractAddress);
    }

    /**
        @notice Test tx success: set gmxVault to a new contract address
     */
    function testSetContractGmxVault() external {
        address currentContractAddress = address(pirexGmx.gmxVault());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.GmxVault, contractAddress);
    }

    /**
        @notice Test tx success: set glpManager to a new contract address
     */
    function testSetContractGlpManager() external {
        address currentContractAddress = address(pirexGmx.glpManager());
        address contractAddress = address(this);

        assertFalse(currentContractAddress == contractAddress);

        _setContract(PirexGmx.Contracts.GlpManager, contractAddress);
    }

    /*//////////////////////////////////////////////////////////////
                        depositGmx TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGmxPaused() external {
        _pauseContract();

        uint256 assets = 1;
        address receiver = address(this);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositGmx(assets, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotDepositGmxAssetsZeroAmount() external {
        uint256 invalidAssets = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGmx(invalidAssets, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGmxReceiverZeroAddress() external {
        uint256 assets = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGmx(assets, invalidReceiver);
    }

    /**
        @notice Test tx reversion: insufficient GMX balance
        @param  assets      uint80  GMX amount
        @param  mintAmount  uint80  GMX mint amount
     */
    function testCannotDepositGmxInsufficientBalance(
        uint80 assets,
        uint80 mintAmount
    ) external {
        vm.assume(assets != 0);
        vm.assume(mintAmount < assets);

        address receiver = address(this);

        _mintApproveGmx(
            mintAmount,
            address(this),
            address(pirexGmx),
            mintAmount
        );

        vm.expectRevert("TRANSFER_FROM_FAILED");

        pirexGmx.depositGmx(assets, receiver);
    }

    /**
        @notice Test tx success: deposit GMX for pxGMX
        @param  depositFee      uint24  Deposit fee
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  separateCaller  bool    Whether to separate method caller and receiver
     */
    function testDepositGmx(
        uint24 depositFee,
        uint8 multiplier,
        bool separateCaller
    ) external {
        vm.assume(depositFee <= feeMax);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _setFee(PirexGmx.Fees.Deposit, depositFee);

        uint256 expectedPreDepositGmxBalancePirexGmx = 0;
        uint256 expectedPreDepositPxGmxSupply = 0;

        assertEq(
            expectedPreDepositGmxBalancePirexGmx,
            rewardTrackerGmx.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPreDepositPxGmxSupply, pxGmx.totalSupply());

        // Deposits GMX, verifies event emission, and validates depositGmx return values
        uint256[] memory depositAmounts = _depositGmxForTestAccounts(
            separateCaller,
            address(this),
            multiplier
        );

        // Assign the initial post-deposit values to their pre-deposit counterparts
        uint256 expectedPostDepositGmxBalancePirexGmx = expectedPreDepositGmxBalancePirexGmx;
        uint256 expectedPostDepositPxGmxSupply = expectedPreDepositPxGmxSupply;
        uint256 tLen = testAccounts.length;

        for (uint256 i; i < tLen; ++i) {
            uint256 depositAmount = depositAmounts[i];

            expectedPostDepositGmxBalancePirexGmx += depositAmount;
            expectedPostDepositPxGmxSupply += depositAmount;

            (uint256 postFeeAmount, ) = _computeAssetAmounts(
                PirexGmx.Fees.Deposit,
                depositAmount
            );

            // Check test account balances against post-fee pxGMX mint amount
            assertEq(postFeeAmount, pxGmx.balanceOf(testAccounts[i]));
        }

        assertEq(
            expectedPostDepositGmxBalancePirexGmx,
            rewardTrackerGmx.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostDepositPxGmxSupply, pxGmx.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                        depositFsGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositFsGlpPaused() external {
        _pauseContract();

        uint256 assets = 1;
        address receiver = address(this);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositFsGlp(assets, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotDepositFsGlpAssetsZeroAmount() external {
        uint256 invalidAssets = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositFsGlp(invalidAssets, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositFsGlpReceiverZeroAddress() external {
        uint256 assets = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositFsGlp(assets, invalidReceiver);
    }

    /**
        @notice Test tx reversion: insufficient fsGLP balance
        @param  ethAmount  uint72  ETH amount
     */
    function testCannotDepositFsGlpInsufficientBalance(uint72 ethAmount)
        external
    {
        vm.assume(ethAmount > 0.001 ether);
        vm.assume(ethAmount < 1000 ether);

        uint256 invalidAssets = _mintAndApproveFsGlp(ethAmount, address(this)) +
            1;
        address receiver = testAccounts[0];

        vm.expectRevert("StakedGlp: transfer amount exceeds allowance");

        pirexGmx.depositFsGlp(invalidAssets, receiver);
    }

    /**
        @notice Test tx success: deposit fsGLP for pxGLP
        @param  depositFee      uint24  Deposit fee
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  separateCaller  bool    Whether to separate method caller and receiver
     */
    function testDepositFsGlp(
        uint24 depositFee,
        uint8 multiplier,
        bool separateCaller
    ) external {
        vm.assume(depositFee <= feeMax);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _setFee(PirexGmx.Fees.Deposit, depositFee);

        uint256 tLen = testAccounts.length;
        uint256 expectedPreDepositGlpBalancePirexGmx = 0;
        uint256 expectedPreDepositPxGlpSupply = 0;

        assertEq(
            expectedPreDepositGlpBalancePirexGmx,
            feeStakedGlp.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPreDepositPxGlpSupply, pxGlp.totalSupply());

        uint256 expectedPostDepositGlpBalancePirexGmx = expectedPreDepositGlpBalancePirexGmx;
        uint256 expectedPostDepositPxGlpSupply = expectedPreDepositPxGlpSupply;

        for (uint256 i; i < tLen; ++i) {
            address testAccount = testAccounts[i];
            address caller = separateCaller ? address(this) : testAccount;
            uint256 assets = _mintAndApproveFsGlp(1 ether * multiplier, caller);
            address receiver = testAccount;

            vm.prank(caller);
            vm.expectEmit(true, true, true, false, address(pirexGmx));

            emit DepositGlp(
                caller,
                receiver,
                address(STAKED_GLP),
                0,
                0,
                0,
                0,
                0,
                0
            );

            (uint256 deposited, uint256 postFeeAmount, ) = pirexGmx
                .depositFsGlp(assets, receiver);
            uint256 receiverPxGlpBalance = pxGlp.balanceOf(receiver);

            expectedPostDepositGlpBalancePirexGmx += deposited;
            expectedPostDepositPxGlpSupply += deposited;

            assertLt(0, receiverPxGlpBalance);
            assertEq(postFeeAmount, receiverPxGlpBalance);
        }

        assertEq(
            expectedPostDepositGlpBalancePirexGmx,
            feeStakedGlp.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostDepositPxGlpSupply, pxGlp.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                        depositGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGlpETHPaused() external {
        _pauseContract();

        uint256 etherAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositGlpETH{value: etherAmount}(minUsdg, minGlp, receiver);
    }

    /**
        @notice Test tx reversion: msg.value is zero
     */
    function testCannotDepositGlpETHMsgValueZeroAmount() external {
        uint256 invalidEtherAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlpETH{value: invalidEtherAmount}(
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minUsdg is zero
     */
    function testCannotDepositGlpETHMinUsdgZeroAmount() external {
        uint256 etherAmount = 1 ether;
        uint256 invalidMinUsdg = 0;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlpETH{value: etherAmount}(
            invalidMinUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is zero
     */
    function testCannotDepositGlpETHMinGlpZeroAmount() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = 0;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlpETH{value: etherAmount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGlpETHReceiverZeroAddress() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGlpETH{value: etherAmount}(
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is greater than output
     */
    function testCannotDepositGlpETHMinGlpInsufficientGlp() external {
        uint256 etherAmount = 1 ether;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = _calculateMinGlpAmount(
            address(0),
            etherAmount,
            18
        ) * 2;
        address receiver = address(this);

        vm.deal(address(this), etherAmount);
        vm.expectRevert(INSUFFICIENT_GLP_OUTPUT_ERROR);

        pirexGmx.depositGlpETH{value: etherAmount}(
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    // /**
    //     @notice Test tx success: testDepositGlp fuzz test covers both methods
    //  */
    // function testDepositGlpETH() external {}

    /*//////////////////////////////////////////////////////////////
                        depositGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotDepositGlpPaused() external {
        _pauseContract();

        address token = address(weth);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.depositGlp(token, tokenAmount, minUsdg, minGlp, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotDepositGlpTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGlp(
            invalidToken,
            tokenAmount,
            minUsdg,
            minGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: token is not whitelisted by GMX
     */
    function testCannotDepositGlpInvalidToken() external {
        address invalidToken = address(this);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(
            abi.encodeWithSelector(PirexGmx.InvalidToken.selector, invalidToken)
        );

        pirexGmx.depositGlp(
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
    function testCannotDepositGlpTokenAmountZeroAmount() external {
        address token = address(weth);
        uint256 invalidTokenAmount = 0;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlp(
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

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlp(
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

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotDepositGlpReceiverZeroAddress() external {
        address token = address(weth);
        uint256 tokenAmount = 1;
        uint256 minUsdg = 1;
        uint256 minGlp = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            invalidReceiver
        );
    }

    /**
        @notice Test tx reversion: minGlp is greater than output
     */
    function testCannotDepositGlpMinGlpInsufficientGlpOutput() external {
        address token = address(weth);
        uint256 tokenAmount = 1e8;
        uint256 minUsdg = 1;
        uint256 invalidMinGlp = _calculateMinGlpAmount(token, tokenAmount, 8) *
            2;
        address receiver = address(this);

        _mintWrappedToken(tokenAmount, address(this));
        weth.approve(address(pirexGmx), tokenAmount);

        vm.expectRevert(INSUFFICIENT_GLP_OUTPUT_ERROR);

        pirexGmx.depositGlp(
            token,
            tokenAmount,
            minUsdg,
            invalidMinGlp,
            receiver
        );
    }

    /**
        @notice Test tx success: deposit for pxGLP
        @param  depositFee      uint24  Deposit fee
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  separateCaller  bool    Whether to separate method caller and receiver
        @param  useETH          bool     Whether or not to use ETH as the source asset for minting GLP
     */
    function testDepositGlp(
        uint24 depositFee,
        uint8 multiplier,
        bool separateCaller,
        bool useETH
    ) external {
        vm.assume(depositFee <= feeMax);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _setFee(PirexGmx.Fees.Deposit, depositFee);

        uint256 expectedPreDepositGlpBalancePirexGmx = 0;
        uint256 expectedPreDepositPxGlpSupply = 0;

        assertEq(
            expectedPreDepositGlpBalancePirexGmx,
            feeStakedGlp.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPreDepositPxGlpSupply, pxGlp.totalSupply());

        // Deposits GLP, verifies event emission, and validates depositGmx return values
        uint256[] memory depositAmounts = _depositGlpForTestAccounts(
            separateCaller,
            address(this),
            multiplier,
            useETH
        );

        // Assign the initial post-deposit values to their pre-deposit counterparts
        uint256 expectedPostDepositGlpBalancePirexGmx = expectedPreDepositGlpBalancePirexGmx;
        uint256 expectedPostDepositPxGlpSupply = expectedPreDepositPxGlpSupply;
        uint256 tLen = testAccounts.length;

        for (uint256 i; i < tLen; ++i) {
            uint256 depositAmount = depositAmounts[i];

            expectedPostDepositGlpBalancePirexGmx += depositAmount;
            expectedPostDepositPxGlpSupply += depositAmount;

            (uint256 postFeeAmount, ) = _computeAssetAmounts(
                PirexGmx.Fees.Deposit,
                depositAmount
            );

            // Check test account balances against post-fee pxGMX mint amount
            assertEq(postFeeAmount, pxGlp.balanceOf(testAccounts[i]));
        }

        assertEq(
            expectedPostDepositGlpBalancePirexGmx,
            feeStakedGlp.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostDepositPxGlpSupply, pxGlp.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlpETH TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotRedeemPxGlpETHPaused() external {
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
            1 ether,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 minOut = _calculateMinOutAmount(address(weth), assets);
        address receiver = testAccounts[0];

        // Pause after deposit
        _pauseContract();

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.redeemPxGlpETH(assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotRedeemPxGlpETHAssetsZeroAmount() external {
        uint256 invalidAssets = 0;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlpETH(invalidAssets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: minOut is zero
     */
    function testCannotRedeemPxGlpETHMinOutZeroAmount() external {
        uint256 assets = 1;
        uint256 invalidMinOut = 0;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlpETH(assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotRedeemPxGlpETHReceiverZeroAddress() external {
        uint256 assets = 1;
        uint256 minOut = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.redeemPxGlpETH(assets, minOut, invalidReceiver);
    }

    /**
        @notice Test tx reversion: minOut is greater than output
     */
    function testCannotRedeemPxGlpETHMinOutInsufficientOutput() external {
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
            1 ether,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 invalidMinOut = _calculateMinOutAmount(address(weth), assets) *
            2;
        address receiver = testAccounts[0];

        vm.expectRevert(INSUFFICIENT_OUTPUT_ERROR);

        pirexGmx.redeemPxGlpETH(assets, invalidMinOut, receiver);
    }

    // /**
    //     @notice Test tx success: testRedeemPxGlp fuzz test covers both methods
    //  */
    // function testRedeemPxGlpETH() external {}

    /*//////////////////////////////////////////////////////////////
                        redeemPxGlp TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotRedeemPxGlpPaused() external {
        uint256 etherAmount = 1 ether;
        address token = address(weth);
        (uint256 postFeeAmount, uint256 feeAmount) = _depositGlpETH(
            etherAmount,
            address(this)
        );
        uint256 assets = postFeeAmount + feeAmount;
        uint256 minOut = _calculateMinOutAmount(token, assets);
        address receiver = testAccounts[0];

        // Pause after deposit
        _pauseContract();

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.redeemPxGlp(token, assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotRedeemPxGlpTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 assets = 1;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.redeemPxGlp(invalidToken, assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: token is not whitelisted by GMX
     */
    function testCannotRedeemPxGlpInvalidToken() external {
        address invalidToken = address(this);
        uint256 assets = 1;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(
            abi.encodeWithSelector(PirexGmx.InvalidToken.selector, invalidToken)
        );

        pirexGmx.redeemPxGlp(invalidToken, assets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: assets is zero
     */
    function testCannotRedeemPxGlpAssetsZeroAmount() external {
        address token = address(weth);
        uint256 invalidAssets = 0;
        uint256 minOut = 1;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlp(token, invalidAssets, minOut, receiver);
    }

    /**
        @notice Test tx reversion: minOut is zero
     */
    function testCannotRedeemPxGlpMinOutZeroAmount() external {
        address token = address(weth);
        uint256 assets = 1;
        uint256 invalidMinOut = 0;
        address receiver = testAccounts[0];

        vm.expectRevert(PirexGmx.ZeroAmount.selector);

        pirexGmx.redeemPxGlp(token, assets, invalidMinOut, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotRedeemPxGlpReceiverZeroAddress() external {
        address token = address(weth);
        uint256 assets = 1;
        uint256 minOut = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.redeemPxGlp(token, assets, minOut, invalidReceiver);
    }

    /**
        @notice Test tx reversion: minOut is greater than output amount
     */
    function testCannotRedeemPxGlpMinOutInsufficientOutput() external {
        address token = address(weth);
        (uint256 deposited, , ) = _depositGlp(1e8, address(this));
        uint256 invalidMinOut = _calculateMinOutAmount(token, deposited) * 2;
        address receiver = testAccounts[0];

        vm.expectRevert(INSUFFICIENT_OUTPUT_ERROR);

        pirexGmx.redeemPxGlp(token, deposited, invalidMinOut, receiver);
    }

    /**
        @notice Test tx success: redeem pxGLP
        @param  redemptionFee   uint24  Redemption fee
        @param  multiplier      uint8   Multiplied with fixed token amounts for randomness
        @param  useETH          bool    Whether or not to use ETH as the source asset for minting GLP
     */
    function testRedeemPxGlp(
        uint24 redemptionFee,
        uint8 multiplier,
        bool useETH
    ) external {
        vm.assume(redemptionFee <= feeMax);
        vm.assume(multiplier != 0);
        vm.assume(multiplier < 10);

        _setFee(PirexGmx.Fees.Redemption, redemptionFee);

        uint256[] memory depositAmounts = _depositGlpForTestAccounts(
            false,
            address(this),
            multiplier,
            useETH
        );

        vm.warp(block.timestamp + 1 days);

        uint256 tLen = testAccounts.length;
        uint256 totalDeposits;

        for (uint256 i; i < tLen; ++i) {
            totalDeposits += depositAmounts[i];
        }

        uint256 expectedPreRedeemGlpBalancePirexGmx = totalDeposits;
        uint256 expectedPreRedeemPxGlpSupply = totalDeposits;

        assertEq(
            expectedPreRedeemGlpBalancePirexGmx,
            feeStakedGlp.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPreRedeemGlpBalancePirexGmx, pxGlp.totalSupply());

        uint256 expectedPostRedeemGlpBalancePirexGmx = expectedPreRedeemGlpBalancePirexGmx;
        uint256 expectedPostRedeemPxGlpSupply = expectedPreRedeemPxGlpSupply;

        for (uint256 i; i < tLen; ++i) {
            address testAccount = testAccounts[i];
            uint256 depositAmount = depositAmounts[i];
            (uint256 postFeeAmount, ) = _computeAssetAmounts(
                PirexGmx.Fees.Redemption,
                depositAmount
            );
            address token = address(weth);

            vm.startPrank(testAccount);

            pxGlp.approve(address(pirexGmx), depositAmount);

            vm.expectEmit(true, true, true, false, address(pirexGmx));

            emit RedeemGlp(
                testAccount,
                testAccount,
                useETH ? address(0) : token,
                0,
                _calculateMinOutAmount(token, postFeeAmount),
                0,
                0,
                0
            );

            (, uint256 returnedPostFeeAmount, ) = useETH
                ? pirexGmx.redeemPxGlpETH(
                    depositAmount,
                    _calculateMinOutAmount(token, postFeeAmount),
                    testAccount
                )
                : pirexGmx.redeemPxGlp(
                    token,
                    depositAmount,
                    _calculateMinOutAmount(token, postFeeAmount),
                    testAccount
                );

            vm.stopPrank();

            expectedPostRedeemGlpBalancePirexGmx -= returnedPostFeeAmount;
            expectedPostRedeemPxGlpSupply -= returnedPostFeeAmount;
        }

        assertEq(
            expectedPostRedeemGlpBalancePirexGmx,
            feeStakedGlp.balanceOf(address(pirexGmx))
        );
        assertEq(expectedPostRedeemPxGlpSupply, pxGlp.totalSupply());
    }

    /*//////////////////////////////////////////////////////////////
                        claimRewards TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimRewardsNotPirexRewards() external {
        assertTrue(address(this) != pirexGmx.pirexRewards());

        vm.expectRevert(PirexGmx.NotPirexRewards.selector);

        pirexGmx.claimRewards();
    }

    /**
        @notice Test tx success: claim WETH, esGMX, and bnGMX/MP rewards
        @param  secondsElapsed  uint32  Seconds to forward timestamp
        @param  tokenAmount     uint72  Amount of wrapped token used for minting GLP
        @param  gmxAmount       uint80  Amount of GMX to mint and deposit
     */
    function testClaimRewards(
        uint32 secondsElapsed,
        uint72 tokenAmount,
        uint80 gmxAmount
    ) external {
        vm.assume(secondsElapsed > 10);
        vm.assume(secondsElapsed < 365 days);
        vm.assume(tokenAmount > 0.001 ether);
        vm.assume(tokenAmount < 1000 ether);
        vm.assume(gmxAmount > 1e15);
        vm.assume(gmxAmount < 1000000e18);

        _depositGlp(tokenAmount, address(this));
        _depositGmx(gmxAmount, address(this));

        vm.warp(block.timestamp + secondsElapsed);

        // Commented out due to "Stack too deep..." error
        // uint256 expectedWethBalanceBeforeClaim = 0;
        // uint256 expectedEsGmxBalanceBeforeClaim = 0;

        assertEq(0, weth.balanceOf(address(pirexGmx)));
        assertEq(0, stakedGmx.depositBalances(address(pirexGmx), esGmx));

        uint256 previousStakedGmxBalance = rewardTrackerGmx.balanceOf(
            address(pirexGmx)
        );
        uint256 expectedWETHRewardsGmx = _calculateRewards(
            address(pirexGmx),
            true,
            true
        );
        uint256 expectedWETHRewardsGlp = _calculateRewards(
            address(pirexGmx),
            true,
            false
        );
        uint256 expectedEsGmxRewardsGmx = _calculateRewards(
            address(pirexGmx),
            false,
            true
        );
        uint256 expectedEsGmxRewardsGlp = _calculateRewards(
            address(pirexGmx),
            false,
            false
        );
        uint256 expectedBnGmxRewards = calculateBnGmxRewards(address(pirexGmx));
        uint256 expectedWETHRewards = expectedWETHRewardsGmx +
            expectedWETHRewardsGlp;
        uint256 expectedEsGmxRewards = expectedEsGmxRewardsGmx +
            expectedEsGmxRewardsGlp;

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        // Limited variable counts due to stack-too-deep issue
        emit ClaimRewards(
            expectedWETHRewards,
            expectedEsGmxRewards,
            expectedWETHRewardsGmx,
            expectedWETHRewardsGlp,
            expectedEsGmxRewardsGmx,
            expectedEsGmxRewardsGlp
        );

        // Impersonate pirexRewards and claim WETH rewards
        vm.prank(address(pirexRewards));

        (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = pirexGmx.claimRewards();

        assertEq(address(pxGmx), address(producerTokens[0]));
        assertEq(address(pxGlp), address(producerTokens[1]));
        assertEq(address(pxGmx), address(producerTokens[2]));
        assertEq(address(pxGlp), address(producerTokens[3]));
        assertEq(address(weth), address(rewardTokens[0]));
        assertEq(address(weth), address(rewardTokens[1]));
        assertEq(address(pxGmx), address(rewardTokens[2]));
        assertEq(address(pxGmx), address(rewardTokens[3]));
        assertEq(expectedWETHRewardsGmx, rewardAmounts[0]);
        assertEq(expectedWETHRewardsGlp, rewardAmounts[1]);
        assertEq(expectedEsGmxRewardsGmx, rewardAmounts[2]);
        assertEq(expectedEsGmxRewardsGlp, rewardAmounts[3]);

        // Commented out due to "Stack too deep..." error
        // uint256 expectedWethBalanceAfterClaim = expectedWETHRewards;
        // uint256 expectedEsGmxBalanceAfterClaim = expectedEsGmxRewards;

        assertEq(expectedWETHRewards, weth.balanceOf(address(pirexGmx)));
        assertEq(
            expectedEsGmxRewards,
            stakedGmx.depositBalances(address(pirexGmx), esGmx)
        );

        // Claimable reward amounts should all be zero post-claim
        assertEq(0, _calculateRewards(address(pirexGmx), true, true));
        assertEq(0, _calculateRewards(address(pirexGmx), true, false));
        assertEq(0, _calculateRewards(address(pirexGmx), false, true));
        assertEq(0, _calculateRewards(address(pirexGmx), false, false));
        assertEq(0, calculateBnGmxRewards(address(pirexGmx)));

        // Claimed esGMX rewards + MP should also be staked immediately
        assertEq(
            previousStakedGmxBalance +
                expectedEsGmxRewards +
                expectedBnGmxRewards,
            rewardTrackerGmx.balanceOf(address(pirexGmx))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        claimUserReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is not pirexRewards
     */
    function testCannotClaimUserRewardNotPirexRewards() external {
        address token = address(weth);
        uint256 amount = 1;
        address receiver = address(this);

        assertTrue(address(this) != pirexGmx.pirexRewards());

        vm.expectRevert(PirexGmx.NotPirexRewards.selector);

        pirexGmx.claimUserReward(token, amount, receiver);
    }

    /**
        @notice Test tx reversion: token is zero address
     */
    function testCannotClaimUserRewardTokenZeroAddress() external {
        address invalidToken = address(0);
        uint256 amount = 1;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);
        vm.prank(address(pirexRewards));

        pirexGmx.claimUserReward(invalidToken, amount, receiver);
    }

    /**
        @notice Test tx reversion: amount is zero
     */
    function testCannotClaimUserRewardAmountZeroAmount() external {
        address token = address(weth);
        uint256 invalidAmount = 0;
        address receiver = address(this);

        vm.expectRevert(PirexGmx.ZeroAmount.selector);
        vm.prank(address(pirexRewards));

        pirexGmx.claimUserReward(token, invalidAmount, receiver);
    }

    /**
        @notice Test tx reversion: receiver is zero address
     */
    function testCannotClaimUserRewardRecipientZeroAddress() external {
        address token = address(weth);
        uint256 amount = 1;
        address invalidReceiver = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);
        vm.prank(address(pirexRewards));

        pirexGmx.claimUserReward(token, amount, invalidReceiver);
    }

    /**
        @notice Test tx success: claim user reward
        @param  wethAmount   uint72  Amount of claimable WETH
        @param  pxGmxAmount  uint80  Amount of claimable pxGMX
     */
    function testClaimUserReward(uint72 wethAmount, uint80 pxGmxAmount)
        external
    {
        vm.assume(wethAmount > 0.001 ether);
        vm.assume(wethAmount < 1000 ether);
        vm.assume(pxGmxAmount != 0);
        vm.assume(pxGmxAmount < 1000000e18);

        address tokenWeth = address(weth);
        address tokenPxGmx = address(pxGmx);
        address receiver = address(this);

        assertEq(0, weth.balanceOf(receiver));
        assertEq(0, pxGmx.balanceOf(receiver));

        // Mint and transfers tokens for user claim tests
        vm.deal(address(this), wethAmount);

        _mintWrappedToken(wethAmount, address(pirexGmx));

        vm.prank(address(pirexGmx));

        pxGmx.mint(address(pirexGmx), pxGmxAmount);

        // Test claim via PirexRewards contract
        vm.startPrank(address(pirexRewards));

        pirexGmx.claimUserReward(tokenWeth, wethAmount, receiver);
        pirexGmx.claimUserReward(tokenPxGmx, pxGmxAmount, receiver);

        vm.stopPrank();

        assertEq(weth.balanceOf(receiver), wethAmount);
        assertEq(pxGmx.balanceOf(receiver), pxGmxAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        setDelegationSpace TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetDelegationSpaceUnauthorized() external {
        string memory space = "test.eth";
        bool clear = false;
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setDelegationSpace(space, clear);
    }

    /**
        @notice Test tx reversion: space is empty string
     */
    function testCannotSetDelegationSpaceEmptyString() external {
        string memory invalidSpace = "";
        bool clear = false;

        vm.expectRevert(PirexGmx.EmptyString.selector);

        pirexGmx.setDelegationSpace(invalidSpace, clear);
    }

    /**
        @notice Test tx success: set delegation space
        @param  clear  bool  Whether to clear the vote delegate
     */
    function testSetDelegationSpace(bool clear) external {
        DelegateRegistry d = DelegateRegistry(pirexGmx.delegateRegistry());
        address voteDelegate = address(this);

        // Set the vote delegate before clearing it when setting new delegation space
        pirexGmx.setVoteDelegate(voteDelegate);

        assertEq(delegationSpace, pirexGmx.delegationSpace());
        assertEq(
            voteDelegate,
            d.delegation(address(pirexGmx), delegationSpace)
        );

        string memory space = "new.eth";
        bytes32 expectedDelegationSpace = bytes32(bytes(space));
        address expectedVoteDelegate = clear ? address(0) : voteDelegate;

        assertFalse(expectedDelegationSpace == delegationSpace);

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit SetDelegationSpace(space, clear);

        pirexGmx.setDelegationSpace(space, clear);

        assertEq(expectedDelegationSpace, pirexGmx.delegationSpace());
        assertEq(
            expectedVoteDelegate,
            d.delegation(address(pirexGmx), delegationSpace)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setVoteDelegate TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetVoteDelegateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();
        address delegate = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setVoteDelegate(delegate);
    }

    /**
        @notice Test tx reversion: delegate is zero address
     */
    function testCannotSetVoteDelegateDelegateZeroAddress() external {
        address invalidDelegate = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.setVoteDelegate(invalidDelegate);
    }

    /**
        @notice Test tx success: set vote delegate
     */
    function testSetVoteDelegate() external {
        address oldDelegate = delegateRegistry.delegation(
            address(pirexGmx),
            pirexGmx.delegationSpace()
        );
        address newDelegate = address(this);

        assertTrue(oldDelegate != newDelegate);

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit SetVoteDelegate(newDelegate);

        pirexGmx.setVoteDelegate(newDelegate);

        address delegate = delegateRegistry.delegation(
            address(pirexGmx),
            pirexGmx.delegationSpace()
        );

        assertEq(delegate, newDelegate);
    }

    /*//////////////////////////////////////////////////////////////
                        clearVoteDelegate TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotClearVoteDelegateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.clearVoteDelegate();
    }

    /**
        @notice Test tx reversion: clear with no delegate set
     */
    function testCannotClearVoteDelegateNoDelegate() external {
        assertEq(
            address(0),
            delegateRegistry.delegation(
                address(pirexGmx),
                pirexGmx.delegationSpace()
            )
        );

        vm.expectRevert("No delegate set");

        pirexGmx.clearVoteDelegate();
    }

    /**
        @notice Test tx success: clear vote delegate
     */
    function testClearVoteDelegate() external {
        pirexGmx.setDelegationSpace("test.eth", false);

        address voteDelegate = address(this);

        // Set the vote delegate before clearing it when setting new delegation space
        pirexGmx.setVoteDelegate(voteDelegate);

        assertEq(
            voteDelegate,
            delegateRegistry.delegation(
                address(pirexGmx),
                pirexGmx.delegationSpace()
            )
        );

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit ClearVoteDelegate();

        pirexGmx.clearVoteDelegate();

        assertEq(
            address(0),
            delegateRegistry.delegation(
                address(pirexGmx),
                pirexGmx.delegationSpace()
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                        setPauseState TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotSetPauseStateUnauthorized() external {
        address unauthorizedCaller = _getUnauthorizedCaller();

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.setPauseState(true);
    }

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotSetPauseStateNotPaused() external {
        assertEq(false, pirexGmx.paused());

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.setPauseState(false);
    }

    /**
        @notice Test tx reversion: contract is paused
     */
    function testCannotSetPauseStatePaused() external {
        _pauseContract();

        vm.expectRevert(PAUSED_ERROR);

        pirexGmx.setPauseState(true);
    }

    /**
        @notice Test tx success: set pause state
     */
    function testSetPauseState() external {
        assertEq(false, pirexGmx.paused());

        _pauseContract();

        pirexGmx.setPauseState(false);

        assertEq(false, pirexGmx.paused());
    }

    /*//////////////////////////////////////////////////////////////
                        initiateMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotInitiateMigrationNotPaused() external {
        assertEq(false, pirexGmx.paused());

        address newContract = address(this);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotInitiateMigrationUnauthorized() external {
        _pauseContract();

        address unauthorizedCaller = _getUnauthorizedCaller();
        address newContract = address(this);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.initiateMigration(newContract);
    }

    /**
        @notice Test tx reversion: newContract is zero address
     */
    function testCannotInitiateMigrationNewContractZeroAddress() external {
        _pauseContract();

        address invalidNewContract = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.initiateMigration(invalidNewContract);
    }

    /**
        @notice Test tx success: initiate migration
     */
    function testInitiateMigration() external {
        _pauseContract();

        address oldContract = address(pirexGmx);
        address newContract = address(this);
        address expectedPendingReceiverBeforeInitation = address(0);

        assertEq(
            expectedPendingReceiverBeforeInitation,
            REWARD_ROUTER_V2.pendingReceivers(oldContract)
        );

        vm.expectEmit(false, false, false, true, address(pirexGmx));

        emit InitiateMigration(newContract);

        pirexGmx.initiateMigration(newContract);

        address expectedPendingReceiverAfterInitation = newContract;

        // Should properly set the pendingReceivers state
        assertEq(
            expectedPendingReceiverAfterInitation,
            REWARD_ROUTER_V2.pendingReceivers(oldContract)
        );

        // Should also set the migratedTo state variable
        assertEq(expectedPendingReceiverAfterInitation, pirexGmx.migratedTo());
    }

    /*//////////////////////////////////////////////////////////////
                        migrateReward TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotMigrateRewardNotPaused() external {
        assertEq(false, pirexGmx.paused());

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.migrateReward();
    }

    /**
        @notice Test tx reversion: caller is not the migration target
     */
    function testCannotMigrateRewardNotMigratedTo() external {
        _pauseContract();

        vm.expectRevert(PirexGmx.NotMigratedTo.selector);

        pirexGmx.migrateReward();
    }

    /**
        @notice Test tx reversion: pending migration exists
     */
    function testCannotMigrateRewardPendingMigration() external {
        _pauseContract();

        uint96 rewardAmount = 1 ether;
        address oldContract = address(pirexGmx);
        address newContract = address(this);

        // Test with WETH as the base reward token
        _mintWrappedToken(rewardAmount, oldContract);

        pirexGmx.initiateMigration(newContract);

        vm.expectRevert(PirexGmx.PendingMigration.selector);

        vm.prank(newContract);

        // Should revert since the method should only be done after full migration
        pirexGmx.migrateReward();
    }

    /**
        @notice Test tx success: migrate base reward
        @param  rewardAmount  uint96  Reward amount
     */
    function testMigrateReward(uint96 rewardAmount) external {
        vm.assume(rewardAmount != 0);
        vm.assume(rewardAmount < 1000 ether);

        _pauseContract();

        address oldContract = address(pirexGmx);
        address newContract = address(this);

        // Test with WETH as the base reward token
        _mintWrappedToken(rewardAmount, oldContract);

        pirexGmx.initiateMigration(newContract);

        // Simulate full migration without triggering migrateReward
        // so we can test it separately
        vm.startPrank(newContract);

        pirexRewards.harvest();

        REWARD_ROUTER_V2.acceptTransfer(oldContract);

        pirexGmx.migrateReward();

        vm.stopPrank();

        // Confirm the base reward balances for both contracts
        assertEq(0, weth.balanceOf(oldContract));
        assertEq(rewardAmount, weth.balanceOf(newContract));
    }

    /*//////////////////////////////////////////////////////////////
                        completeMigration TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: contract is not paused
     */
    function testCannotCompleteMigrationNotPaused() external {
        assertEq(false, pirexGmx.paused());

        address oldContract = address(this);

        vm.expectRevert(NOT_PAUSED_ERROR);

        pirexGmx.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion: caller is unauthorized
     */
    function testCannotCompleteMigrationUnauthorized() external {
        _pauseContract();

        address unauthorizedCaller = _getUnauthorizedCaller();
        address oldContract = address(pirexGmx);

        vm.expectRevert(UNAUTHORIZED_ERROR);
        vm.prank(unauthorizedCaller);

        pirexGmx.completeMigration(oldContract);
    }

    /**
        @notice Test tx reversion: oldContract is zero address
     */
    function testCannotCompleteMigrationZeroAddress() external {
        _pauseContract();

        address invalidOldContract = address(0);

        vm.expectRevert(PirexGmx.ZeroAddress.selector);

        pirexGmx.completeMigration(invalidOldContract);
    }

    /**
        @notice Test tx reversion due to the caller not being the assigned new contract
     */
    function testCannotCompleteMigrationInvalidNewContract() external {
        _pauseContract();

        address oldContract = address(pirexGmx);
        address newContract = address(this);

        pirexGmx.initiateMigration(newContract);

        assertEq(newContract, REWARD_ROUTER_V2.pendingReceivers(oldContract));

        // Deploy a test contract but not assign it as the migration target
        PirexGmx newPirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry),
            REWARD_ROUTER_V2.weth(),
            REWARD_ROUTER_V2.gmx(),
            REWARD_ROUTER_V2.esGmx(),
            address(REWARD_ROUTER_V2),
            address(STAKED_GLP)
        );

        vm.expectRevert("RewardRouter: transfer not signalled");

        newPirexGmx.completeMigration(oldContract);
    }

    /**
        @notice Test tx success: completing migration
     */
    function testCompleteMigration() external {
        // Perform GMX deposit for balance tests after migration
        uint256 assets = 1e18;
        address receiver = address(this);
        address oldContract = address(pirexGmx);

        _mintApproveGmx(assets, address(this), oldContract, assets);
        pirexGmx.depositGmx(assets, receiver);

        // Perform GLP deposit for balance tests after migration
        uint256 etherAmount = 1 ether;

        vm.deal(address(this), etherAmount);

        pirexGmx.depositGlpETH{value: etherAmount}(1, 1, receiver);

        // Time skip to bypass the cooldown duration
        vm.warp(block.timestamp + 1 days);

        // Store the staked balances and rewards for later validations
        uint256 oldStakedGmxBalance = rewardTrackerGmx.balanceOf(oldContract);
        uint256 oldStakedGlpBalance = feeStakedGlp.balanceOf(oldContract);
        uint256 oldEsGmxClaimable = _calculateRewards(
            oldContract,
            false,
            true
        ) + _calculateRewards(oldContract, false, false);
        uint256 oldMpBalance = rewardTrackerMp.claimable(oldContract);
        uint256 oldBaseRewardClaimable = _calculateRewards(
            oldContract,
            true,
            true
        ) + _calculateRewards(oldContract, true, false);

        // Pause the contract before proceeding
        _pauseContract();

        // Deploy the new contract for migration tests
        PirexGmx newPirexGmx = new PirexGmx(
            address(pxGmx),
            address(pxGlp),
            address(pirexFees),
            address(pirexRewards),
            address(delegateRegistry),
            REWARD_ROUTER_V2.weth(),
            REWARD_ROUTER_V2.gmx(),
            REWARD_ROUTER_V2.esGmx(),
            address(REWARD_ROUTER_V2),
            address(STAKED_GLP)
        );

        address newContract = address(newPirexGmx);

        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        pirexGmx.initiateMigration(newContract);

        // Should properly set the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), newContract);

        vm.expectEmit(false, false, false, true, address(newPirexGmx));

        emit CompleteMigration(oldContract);

        // Complete the migration using the new contract
        newPirexGmx.completeMigration(oldContract);

        // Should properly clear the pendingReceivers state
        assertEq(REWARD_ROUTER_V2.pendingReceivers(oldContract), address(0));

        // Confirm that the token balances and claimables for old contract are correct
        assertEq(0, rewardTrackerGmx.balanceOf(oldContract));
        assertEq(0, feeStakedGlp.balanceOf(oldContract));
        assertEq(0, stakedGmx.claimable(oldContract));
        assertEq(0, feeStakedGlp.claimable(oldContract));
        assertEq(0, rewardTrackerMp.claimable(oldContract));

        // Confirm that the staked token balances for new contract are correct
        // For Staked GMX balance, due to compounding in the migration,
        // all pending claimable esGMX and MP are automatically staked
        assertEq(
            oldStakedGmxBalance + oldEsGmxClaimable + oldMpBalance,
            rewardTrackerGmx.balanceOf(newContract)
        );
        assertEq(oldStakedGlpBalance, feeStakedGlp.balanceOf(newContract));

        // Confirm that the remaining base reward has also been migrated
        assertEq(0, pirexGmx.gmxBaseReward().balanceOf(oldContract));
        assertEq(
            oldBaseRewardClaimable,
            pirexGmx.gmxBaseReward().balanceOf(newContract)
        );
    }
}
