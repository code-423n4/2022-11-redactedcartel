// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {Pausable} from "openzeppelin-contracts/contracts/security/Pausable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PxERC20} from "src/PxERC20.sol";
import {PirexFees} from "src/PirexFees.sol";
import {DelegateRegistry} from "src/external/DelegateRegistry.sol";
import {IRewardRouterV2} from "src/interfaces/IRewardRouterV2.sol";
import {RewardTracker} from "src/external/RewardTracker.sol";
import {IStakedGlp} from "src/interfaces/IStakedGlp.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {IRewardDistributor} from "src/interfaces/IRewardDistributor.sol";
import {IPirexRewards} from "src/interfaces/IPirexRewards.sol";
import {IGlpManager} from "src/interfaces/IGlpManager.sol";

contract PirexGmx is ReentrancyGuard, Owned, Pausable {
    using SafeTransferLib for ERC20;

    // Configurable fees
    enum Fees {
        Deposit,
        Redemption,
        Reward
    }

    // Configurable external contracts
    enum Contracts {
        PirexFees,
        RewardRouterV2,
        RewardTrackerGmx,
        RewardTrackerGlp,
        FeeStakedGlp,
        StakedGmx,
        StakedGlp,
        GmxVault,
        GlpManager
    }

    // Fee denominator
    uint256 public constant FEE_DENOMINATOR = 1_000_000;

    // Fee maximum (i.e. 20%)
    uint256 public constant FEE_MAX = 200_000;

    // External token contracts
    ERC20 public immutable gmxBaseReward; // e.g. WETH (Ethereum)
    ERC20 public immutable gmx;
    ERC20 public immutable esGmx;

    // Pirex token contract(s) which are unlikely to change
    PxERC20 public immutable pxGmx;
    PxERC20 public immutable pxGlp;

    // Pirex fee repository and distribution contract
    PirexFees public pirexFees;

    // Pirex reward module contract
    address public immutable pirexRewards;

    // Snapshot vote delegation contract
    DelegateRegistry public immutable delegateRegistry;

    // GMX contracts
    IRewardRouterV2 public gmxRewardRouterV2;
    RewardTracker public rewardTrackerGmx;
    RewardTracker public rewardTrackerGlp;
    RewardTracker public feeStakedGlp;
    RewardTracker public stakedGmx;
    IStakedGlp public stakedGlp;
    address public glpManager;
    IVault public gmxVault;

    // Migration related address
    address public migratedTo;

    // Snapshot space
    bytes32 public delegationSpace = bytes32("gmx.eth");

    // Fees (e.g. 5000 / 1000000 = 0.5%)
    mapping(Fees => uint256) public fees;

    event ConfigureGmxState(
        address indexed caller,
        RewardTracker rewardTrackerGmx,
        RewardTracker rewardTrackerGlp,
        RewardTracker feeStakedGlp,
        RewardTracker stakedGmx,
        address glpManager,
        IVault gmxVault
    );
    event SetFee(Fees indexed f, uint256 fee);
    event SetContract(Contracts indexed c, address contractAddress);
    event DepositGmx(
        address indexed caller,
        address indexed receiver,
        uint256 deposited,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event DepositGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        uint256 deposited,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event RedeemGlp(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256 amount,
        uint256 minOut,
        uint256 redemption,
        uint256 postFeeAmount,
        uint256 feeAmount
    );
    event ClaimRewards(
        uint256 baseRewards,
        uint256 esGmxRewards,
        uint256 gmxBaseRewards,
        uint256 glpBaseRewards,
        uint256 gmxEsGmxRewards,
        uint256 glpEsGmxRewards
    );
    event ClaimUserReward(
        address indexed receiver,
        address indexed token,
        uint256 amount,
        uint256 rewardAmount,
        uint256 feeAmount
    );
    event InitiateMigration(address newContract);
    event CompleteMigration(address oldContract);
    event SetDelegationSpace(string delegationSpace, bool shouldClear);
    event SetVoteDelegate(address voteDelegate);
    event ClearVoteDelegate();

    error ZeroAmount();
    error ZeroAddress();
    error InvalidToken(address token);
    error NotPirexRewards();
    error InvalidFee();
    error EmptyString();
    error NotMigratedTo();
    error PendingMigration();

    /**
        @param  _pxGmx              address  PxGmx contract address
        @param  _pxGlp              address  PxGlp contract address
        @param  _pirexFees          address  PirexFees contract address
        @param  _pirexRewards       address  PirexRewards contract address
        @param  _delegateRegistry   address  Delegation registry contract address
        @param  _gmxBaseReward      address  GMX base reward token contract address
        @param  _gmx                address  GMX token contract address
        @param  _esGmx              address  esGMX token contract address
        @param  _gmxRewardRouterV2  address  GMX Reward Router contract address
        @param  _stakedGlp          address  Staked GLP token contract address
    */
    constructor(
        address _pxGmx,
        address _pxGlp,
        address _pirexFees,
        address _pirexRewards,
        address _delegateRegistry,
        address _gmxBaseReward,
        address _gmx,
        address _esGmx,
        address _gmxRewardRouterV2,
        address _stakedGlp
    ) Owned(msg.sender) {
        // Start the contract paused, to ensure contract set is properly configured
        _pause();

        if (_pxGmx == address(0)) revert ZeroAddress();
        if (_pxGlp == address(0)) revert ZeroAddress();
        if (_pirexFees == address(0)) revert ZeroAddress();
        if (_pirexRewards == address(0)) revert ZeroAddress();
        if (_delegateRegistry == address(0)) revert ZeroAddress();
        if (_gmxBaseReward == address(0)) revert ZeroAddress();
        if (_gmx == address(0)) revert ZeroAddress();
        if (_esGmx == address(0)) revert ZeroAddress();
        if (_gmxRewardRouterV2 == address(0)) revert ZeroAddress();
        if (_stakedGlp == address(0)) revert ZeroAddress();

        pxGmx = PxERC20(_pxGmx);
        pxGlp = PxERC20(_pxGlp);
        pirexFees = PirexFees(_pirexFees);
        pirexRewards = _pirexRewards;
        delegateRegistry = DelegateRegistry(_delegateRegistry);
        gmxBaseReward = ERC20(_gmxBaseReward);
        gmx = ERC20(_gmx);
        esGmx = ERC20(_esGmx);
        gmxRewardRouterV2 = IRewardRouterV2(_gmxRewardRouterV2);
        stakedGlp = IStakedGlp(_stakedGlp);
    }

    modifier onlyPirexRewards() {
        if (msg.sender != pirexRewards) revert NotPirexRewards();
        _;
    }

    /**
        @notice Compute post-fee asset and fee amounts from a fee type and total assets
        @param  f              enum     Fee
        @param  assets         uint256  GMX/GLP/WETH asset amount
        @return postFeeAmount  uint256  Post-fee asset amount (for mint/burn/claim/etc.)
        @return feeAmount      uint256  Fee amount
     */
    function _computeAssetAmounts(Fees f, uint256 assets)
        internal
        view
        returns (uint256 postFeeAmount, uint256 feeAmount)
    {
        feeAmount = (assets * fees[f]) / FEE_DENOMINATOR;
        postFeeAmount = assets - feeAmount;

        assert(feeAmount + postFeeAmount == assets);
    }

    /**
        @notice Calculate the base (e.g. WETH) or esGMX rewards for either GMX or GLP
        @param  isBaseReward  bool     Whether to calculate base or esGMX rewards
        @param  useGmx        bool     Whether the calculation should be for GMX
        @return               uint256  Amount of WETH/esGMX rewards
     */
    function _calculateRewards(bool isBaseReward, bool useGmx)
        internal
        view
        returns (uint256)
    {
        RewardTracker r;

        if (isBaseReward) {
            r = useGmx ? rewardTrackerGmx : rewardTrackerGlp;
        } else {
            r = useGmx ? stakedGmx : feeStakedGlp;
        }

        address distributor = r.distributor();
        uint256 pendingRewards = IRewardDistributor(distributor)
            .pendingRewards();
        uint256 distributorBalance = (isBaseReward ? gmxBaseReward : esGmx)
            .balanceOf(distributor);
        uint256 blockReward = pendingRewards > distributorBalance
            ? distributorBalance
            : pendingRewards;
        uint256 precision = r.PRECISION();
        uint256 cumulativeRewardPerToken = r.cumulativeRewardPerToken() +
            ((blockReward * precision) / r.totalSupply());

        if (cumulativeRewardPerToken == 0) return 0;

        return
            r.claimableReward(address(this)) +
            ((r.stakedAmounts(address(this)) *
                (cumulativeRewardPerToken -
                    r.previousCumulatedRewardPerToken(address(this)))) /
                precision);
    }

    /**
        @notice Configure GMX contract state
     */
    function configureGmxState() external onlyOwner whenPaused {
        // Variables which can be assigned by reading previously-set GMX contracts
        rewardTrackerGmx = RewardTracker(gmxRewardRouterV2.feeGmxTracker());
        rewardTrackerGlp = RewardTracker(gmxRewardRouterV2.feeGlpTracker());
        feeStakedGlp = RewardTracker(gmxRewardRouterV2.stakedGlpTracker());
        stakedGmx = RewardTracker(gmxRewardRouterV2.stakedGmxTracker());
        glpManager = gmxRewardRouterV2.glpManager();
        gmxVault = IVault(IGlpManager(glpManager).vault());

        emit ConfigureGmxState(
            msg.sender,
            rewardTrackerGmx,
            rewardTrackerGlp,
            feeStakedGlp,
            stakedGmx,
            glpManager,
            gmxVault
        );

        // Approve GMX to enable staking
        gmx.safeApprove(address(stakedGmx), type(uint256).max);
    }

    /**
        @notice Set fee
        @param  f    enum     Fee
        @param  fee  uint256  Fee amount
     */
    function setFee(Fees f, uint256 fee) external onlyOwner {
        if (fee > FEE_MAX) revert InvalidFee();

        fees[f] = fee;

        emit SetFee(f, fee);
    }

    /**
        @notice Set a contract address
        @param  c                enum     Contracts
        @param  contractAddress  address  Contract address
     */
    function setContract(Contracts c, address contractAddress)
        external
        onlyOwner
    {
        if (contractAddress == address(0)) revert ZeroAddress();

        emit SetContract(c, contractAddress);

        if (c == Contracts.PirexFees) {
            pirexFees = PirexFees(contractAddress);
            return;
        }

        if (c == Contracts.RewardRouterV2) {
            gmxRewardRouterV2 = IRewardRouterV2(contractAddress);
            return;
        }

        if (c == Contracts.RewardTrackerGmx) {
            rewardTrackerGmx = RewardTracker(contractAddress);
            return;
        }

        if (c == Contracts.RewardTrackerGlp) {
            rewardTrackerGlp = RewardTracker(contractAddress);
            return;
        }

        if (c == Contracts.FeeStakedGlp) {
            feeStakedGlp = RewardTracker(contractAddress);
            return;
        }

        if (c == Contracts.StakedGmx) {
            // Set the current stakedGmx (pending change) approval amount to 0
            gmx.safeApprove(address(stakedGmx), 0);

            stakedGmx = RewardTracker(contractAddress);

            // Approve the new stakedGmx contract address allowance to the max
            gmx.safeApprove(contractAddress, type(uint256).max);
            return;
        }

        if (c == Contracts.StakedGlp) {
            stakedGlp = IStakedGlp(contractAddress);
            return;
        }

        if (c == Contracts.GmxVault) {
            gmxVault = IVault(contractAddress);
            return;
        }

        glpManager = contractAddress;
    }

    /**
        @notice Deposit GMX for pxGMX
        @param  amount    uint256  GMX amount
        @param  receiver  address  pxGMX receiver
        @return           uint256  GMX deposited
        @return           uint256  pxGMX minted for the receiver
        @return           uint256  pxGMX distributed as fees
     */
    function depositGmx(uint256 amount, address receiver)
        external
        whenNotPaused
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Transfer the caller's GMX to this contract and stake it for rewards
        gmx.safeTransferFrom(msg.sender, address(this), amount);
        gmxRewardRouterV2.stakeGmx(amount);

        // Get the pxGMX amounts for the receiver and the protocol (fees)
        (uint256 postFeeAmount, uint256 feeAmount) = _computeAssetAmounts(
            Fees.Deposit,
            amount
        );

        // Mint pxGMX for the receiver (excludes fees)
        pxGmx.mint(receiver, postFeeAmount);

        // Mint pxGMX for fee distribution contract
        if (feeAmount != 0) {
            pxGmx.mint(address(pirexFees), feeAmount);
        }

        emit DepositGmx(msg.sender, receiver, amount, postFeeAmount, feeAmount);

        return (amount, postFeeAmount, feeAmount);
    }

    /**
        @notice Deposit fsGLP for pxGLP
        @param  amount    uint256  fsGLP amount
        @param  receiver  address  pxGLP receiver
        @return           uint256  fsGLP deposited
        @return           uint256  pxGLP minted for the receiver
        @return           uint256  pxGLP distributed as fees
     */
    function depositFsGlp(uint256 amount, address receiver)
        external
        whenNotPaused
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Transfer the caller's fsGLP (unstaked for the user, staked for this contract)
        stakedGlp.transferFrom(msg.sender, address(this), amount);

        // Get the pxGLP amounts for the receiver and the protocol (fees)
        (uint256 postFeeAmount, uint256 feeAmount) = _computeAssetAmounts(
            Fees.Deposit,
            amount
        );

        // Mint pxGLP for the receiver (excludes fees)
        pxGlp.mint(receiver, postFeeAmount);

        // Mint pxGLP for fee distribution contract
        if (feeAmount != 0) {
            pxGlp.mint(address(pirexFees), feeAmount);
        }

        emit DepositGlp(
            msg.sender,
            receiver,
            address(stakedGlp),
            0,
            0,
            0,
            amount,
            postFeeAmount,
            feeAmount
        );

        return (amount, postFeeAmount, feeAmount);
    }

    /**
        @notice Deposit GLP for pxGLP
        @param  token          address  GMX-whitelisted token for minting GLP (optional)
        @param  tokenAmount    uint256  Token amount
        @param  minUsdg        uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp         uint256  Minimum GLP amount minted from tokens
        @param  receiver       address  pxGLP receiver
        @return deposited      uint256  GLP deposited
        @return postFeeAmount  uint256  pxGLP minted for the receiver
        @return feeAmount      uint256  pxGLP distributed as fees
     */
    function _depositGlp(
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    )
        internal
        returns (
            uint256 deposited,
            uint256 postFeeAmount,
            uint256 feeAmount
        )
    {
        if (tokenAmount == 0) revert ZeroAmount();
        if (minUsdg == 0) revert ZeroAmount();
        if (minGlp == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (token == address(0)) {
            // Mint and stake GLP using ETH
            deposited = gmxRewardRouterV2.mintAndStakeGlpETH{
                value: tokenAmount
            }(minUsdg, minGlp);
        } else {
            ERC20 t = ERC20(token);

            // Intake user ERC20 tokens and approve GLP Manager contract for amount
            t.safeTransferFrom(msg.sender, address(this), tokenAmount);
            t.safeApprove(glpManager, tokenAmount);

            // Mint and stake GLP using ERC20 tokens
            deposited = gmxRewardRouterV2.mintAndStakeGlp(
                token,
                tokenAmount,
                minUsdg,
                minGlp
            );
        }

        // Calculate the post-fee and fee amounts based on the fee type and total deposited
        (postFeeAmount, feeAmount) = _computeAssetAmounts(
            Fees.Deposit,
            deposited
        );

        // Mint pxGLP for the receiver
        pxGlp.mint(receiver, postFeeAmount);

        // Mint pxGLP for fee distribution contract
        if (feeAmount != 0) {
            pxGlp.mint(address(pirexFees), feeAmount);
        }

        emit DepositGlp(
            msg.sender,
            receiver,
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            deposited,
            postFeeAmount,
            feeAmount
        );
    }

    /**
        @notice Deposit GLP (minted with ETH) for pxGLP
        @param  minUsdg    uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp     uint256  Minimum GLP amount minted from ETH
        @param  receiver   address  pxGLP receiver
        @return deposited  uint256  GLP deposited
        @return            uint256  pxGLP minted for the receiver
        @return            uint256  pxGLP distributed as fees
     */
    function depositGlpETH(
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    )
        external
        payable
        whenNotPaused
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _depositGlp(address(0), msg.value, minUsdg, minGlp, receiver);
    }

    /**
        @notice Deposit GLP (minted with ERC20 tokens) for pxGLP
        @param  token        address  GMX-whitelisted token for minting GLP
        @param  tokenAmount  uint256  Whitelisted token amount
        @param  minUsdg      uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp       uint256  Minimum GLP amount minted from ERC20 tokens
        @param  receiver     address  pxGLP receiver
        @return              uint256  GLP deposited
        @return              uint256  pxGLP minted for the receiver
        @return              uint256  pxGLP distributed as fees
     */
    function depositGlp(
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    )
        external
        whenNotPaused
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (token == address(0)) revert ZeroAddress();
        if (!gmxVault.whitelistedTokens(token)) revert InvalidToken(token);

        return _depositGlp(token, tokenAmount, minUsdg, minGlp, receiver);
    }

    /**
        @notice Redeem pxGLP
        @param  token          address  GMX-whitelisted token to be redeemed (optional)
        @param  amount         uint256  pxGLP amount
        @param  minOut         uint256  Minimum token output from GLP redemption
        @param  receiver       address  Output token recipient
        @return redeemed       uint256  Output tokens from redeeming GLP
        @return postFeeAmount  uint256  pxGLP burned from the msg.sender
        @return feeAmount      uint256  pxGLP distributed as fees
     */
    function _redeemPxGlp(
        address token,
        uint256 amount,
        uint256 minOut,
        address receiver
    )
        internal
        returns (
            uint256 redeemed,
            uint256 postFeeAmount,
            uint256 feeAmount
        )
    {
        if (amount == 0) revert ZeroAmount();
        if (minOut == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        // Calculate the post-fee and fee amounts based on the fee type and total amount
        (postFeeAmount, feeAmount) = _computeAssetAmounts(
            Fees.Redemption,
            amount
        );

        // Burn pxGLP before redeeming the underlying GLP
        pxGlp.burn(msg.sender, postFeeAmount);

        // Transfer pxGLP from caller to the fee distribution contract
        if (feeAmount != 0) {
            ERC20(pxGlp).safeTransferFrom(
                msg.sender,
                address(pirexFees),
                feeAmount
            );
        }

        // Unstake and redeem the underlying GLP for ERC20 tokens
        redeemed = token == address(0)
            ? gmxRewardRouterV2.unstakeAndRedeemGlpETH(
                postFeeAmount,
                minOut,
                receiver
            )
            : gmxRewardRouterV2.unstakeAndRedeemGlp(
                token,
                postFeeAmount,
                minOut,
                receiver
            );

        emit RedeemGlp(
            msg.sender,
            receiver,
            token,
            amount,
            minOut,
            redeemed,
            postFeeAmount,
            feeAmount
        );
    }

    /**
        @notice Redeem pxGLP for ETH from redeeming GLP
        @param  amount    uint256  pxGLP amount
        @param  minOut    uint256  Minimum ETH output from GLP redemption
        @param  receiver  address  ETH recipient
        @return           uint256  ETH redeemed from GLP
        @return           uint256  pxGLP burned from the msg.sender
        @return           uint256  pxGLP distributed as fees
     */
    function redeemPxGlpETH(
        uint256 amount,
        uint256 minOut,
        address receiver
    )
        external
        whenNotPaused
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return _redeemPxGlp(address(0), amount, minOut, receiver);
    }

    /**
        @notice Redeem pxGLP for ERC20 tokens from redeeming GLP
        @param  token     address  GMX-whitelisted token to be redeemed
        @param  amount    uint256  pxGLP amount
        @param  minOut    uint256  Minimum ERC20 output from GLP redemption
        @param  receiver  address  ERC20 token recipient
        @return           uint256  ERC20 tokens from redeeming GLP
        @return           uint256  pxGLP burned from the msg.sender
        @return           uint256  pxGLP distributed as fees
     */
    function redeemPxGlp(
        address token,
        uint256 amount,
        uint256 minOut,
        address receiver
    )
        external
        whenNotPaused
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        if (token == address(0)) revert ZeroAddress();
        if (!gmxVault.whitelistedTokens(token)) revert InvalidToken(token);

        return _redeemPxGlp(token, amount, minOut, receiver);
    }

    /**
        @notice Claim WETH/esGMX rewards + multiplier points (MP)
        @return producerTokens  ERC20[]    Producer tokens (pxGLP and pxGMX)
        @return rewardTokens    ERC20[]    Reward token contract instances
        @return rewardAmounts   uint256[]  Reward amounts from each producerToken
     */
    function claimRewards()
        external
        onlyPirexRewards
        returns (
            ERC20[] memory producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        // Assign return values used by the PirexRewards contract
        producerTokens = new ERC20[](4);
        rewardTokens = new ERC20[](4);
        rewardAmounts = new uint256[](4);
        producerTokens[0] = pxGmx;
        producerTokens[1] = pxGlp;
        producerTokens[2] = pxGmx;
        producerTokens[3] = pxGlp;
        rewardTokens[0] = gmxBaseReward;
        rewardTokens[1] = gmxBaseReward;
        rewardTokens[2] = ERC20(pxGmx); // esGMX rewards distributed as pxGMX
        rewardTokens[3] = ERC20(pxGmx);

        // Get pre-reward claim reward token balances to calculate actual amount received
        uint256 baseRewardBeforeClaim = gmxBaseReward.balanceOf(address(this));
        uint256 esGmxBeforeClaim = stakedGmx.depositBalances(
            address(this),
            address(esGmx)
        );

        // Calculate the unclaimed reward token amounts produced for each token type
        uint256 gmxBaseRewards = _calculateRewards(true, true);
        uint256 glpBaseRewards = _calculateRewards(true, false);
        uint256 gmxEsGmxRewards = _calculateRewards(false, true);
        uint256 glpEsGmxRewards = _calculateRewards(false, false);

        // Claim and stake esGMX + MP, and claim WETH
        gmxRewardRouterV2.handleRewards(
            false,
            false,
            true,
            true,
            true,
            true,
            false
        );

        uint256 baseRewards = gmxBaseReward.balanceOf(address(this)) -
            baseRewardBeforeClaim;
        uint256 esGmxRewards = stakedGmx.depositBalances(
            address(this),
            address(esGmx)
        ) - esGmxBeforeClaim;

        if (baseRewards != 0) {
            // This may not be necessary and is more of a hedge against a discrepancy between
            // the actual rewards and the calculated amounts. Needs further consideration
            rewardAmounts[0] =
                (gmxBaseRewards * baseRewards) /
                (gmxBaseRewards + glpBaseRewards);
            rewardAmounts[1] = baseRewards - rewardAmounts[0];
        }

        if (esGmxRewards != 0) {
            rewardAmounts[2] =
                (gmxEsGmxRewards * esGmxRewards) /
                (gmxEsGmxRewards + glpEsGmxRewards);
            rewardAmounts[3] = esGmxRewards - rewardAmounts[2];
        }

        emit ClaimRewards(
            baseRewards,
            esGmxRewards,
            gmxBaseRewards,
            glpBaseRewards,
            gmxEsGmxRewards,
            glpEsGmxRewards
        );
    }

    /**
        @notice Mint/transfer the specified reward token to the receiver
        @param  token     address  Reward token address
        @param  amount    uint256  Reward amount
        @param  receiver  address  Reward receiver
     */
    function claimUserReward(
        address token,
        uint256 amount,
        address receiver
    ) external onlyPirexRewards {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        (uint256 postFeeAmount, uint256 feeAmount) = _computeAssetAmounts(
            Fees.Reward,
            amount
        );

        if (token == address(pxGmx)) {
            // Mint pxGMX for the user - the analog for esGMX rewards
            pxGmx.mint(receiver, postFeeAmount);

            if (feeAmount != 0) pxGmx.mint(address(pirexFees), feeAmount);
        } else if (token == address(gmxBaseReward)) {
            gmxBaseReward.safeTransfer(receiver, postFeeAmount);

            if (feeAmount != 0)
                gmxBaseReward.safeTransfer(address(pirexFees), feeAmount);
        }

        emit ClaimUserReward(receiver, token, amount, postFeeAmount, feeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        VOTE DELEGATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Set delegationSpace
        @param  _delegationSpace  string  Snapshot delegation space
        @param  shouldClear       bool    Whether to clear the vote delegate for the current space
     */
    function setDelegationSpace(
        string memory _delegationSpace,
        bool shouldClear
    ) external onlyOwner {
        if (shouldClear) {
            // Clear the delegation for the current delegation space
            clearVoteDelegate();
        }

        bytes memory d = bytes(_delegationSpace);

        if (d.length == 0) revert EmptyString();

        delegationSpace = bytes32(d);

        emit SetDelegationSpace(_delegationSpace, shouldClear);
    }

    /**
        @notice Set vote delegate
        @param  voteDelegate  address  Account to delegate votes to
     */
    function setVoteDelegate(address voteDelegate) external onlyOwner {
        if (voteDelegate == address(0)) revert ZeroAddress();

        emit SetVoteDelegate(voteDelegate);

        delegateRegistry.setDelegate(delegationSpace, voteDelegate);
    }

    /**
        @notice Clear vote delegate
     */
    function clearVoteDelegate() public onlyOwner {
        emit ClearVoteDelegate();

        delegateRegistry.clearDelegate(delegationSpace);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY/MIGRATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Set the contract's pause state
        @param state  bool  Pause state
    */
    function setPauseState(bool state) external onlyOwner {
        if (state) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
        @notice Initiate contract migration (called by the old contract)
        @param  newContract  address  Address of the new contract
    */
    function initiateMigration(address newContract)
        external
        whenPaused
        onlyOwner
    {
        if (newContract == address(0)) revert ZeroAddress();

        // Notify the reward router that the current/old contract is going to perform
        // full account transfer to the specified new contract
        gmxRewardRouterV2.signalTransfer(newContract);

        migratedTo = newContract;

        emit InitiateMigration(newContract);
    }

    /**
        @notice Migrate remaining (base) reward to the new contract after completing migration
    */
    function migrateReward() external whenPaused {
        if (msg.sender != migratedTo) revert NotMigratedTo();
        if (gmxRewardRouterV2.pendingReceivers(address(this)) != address(0))
            revert PendingMigration();

        // Transfer out any remaining base reward (ie. WETH) to the new contract
        gmxBaseReward.safeTransfer(
            migratedTo,
            gmxBaseReward.balanceOf(address(this))
        );
    }

    /**
        @notice Complete contract migration (called by the new contract)
        @param  oldContract  address  Address of the old contract
    */
    function completeMigration(address oldContract)
        external
        whenPaused
        onlyOwner
    {
        if (oldContract == address(0)) revert ZeroAddress();

        // Trigger harvest to claim remaining rewards before the account transfer
        IPirexRewards(pirexRewards).harvest();

        // Complete the full account transfer process
        gmxRewardRouterV2.acceptTransfer(oldContract);

        // Perform reward token transfer from the old contract to the new one
        PirexGmx(oldContract).migrateReward();

        emit CompleteMigration(oldContract);
    }
}
