// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PirexERC4626} from "src/vaults/PirexERC4626.sol";
import {PxGmxReward} from "src/vaults/PxGmxReward.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PirexGmx} from "src/PirexGmx.sol";
import {PirexRewards} from "src/PirexRewards.sol";

contract AutoPxGlp is PirexERC4626, PxGmxReward, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 public constant MAX_WITHDRAWAL_PENALTY = 500;
    uint256 public constant MAX_PLATFORM_FEE = 2000;
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant MAX_COMPOUND_INCENTIVE = 5000;
    uint256 public constant EXPANDED_DECIMALS = 1e30;

    uint256 public withdrawalPenalty = 300;
    uint256 public platformFee = 1000;
    uint256 public compoundIncentive = 1000;
    address public platform;

    // Address of the rewards module (ie. PirexRewards instance)
    address public immutable rewardsModule;

    // GMX protocol base reward (e.g. WETH)
    ERC20 public immutable gmxBaseReward;

    event WithdrawalPenaltyUpdated(uint256 penalty);
    event PlatformFeeUpdated(uint256 fee);
    event CompoundIncentiveUpdated(uint256 incentive);
    event PlatformUpdated(address _platform);
    event Compounded(
        address indexed caller,
        uint256 minGlp,
        uint256 gmxBaseRewardAmount,
        uint256 pxGmxAmountOut,
        uint256 pxGlpAmountOut,
        uint256 totalPxGlpFee,
        uint256 totalPxGmxFee,
        uint256 pxGlpIncentive,
        uint256 pxGmxIncentive
    );

    error ZeroAmount();
    error InvalidAssetParam();
    error ExceedsMax();
    error InvalidParam();
    error ZeroShares();

    /**
        @param  _gmxBaseReward  address  GMX reward token contract address
        @param  _asset          address  Asset address (vault asset, e.g. pxGLP)
        @param  _pxGmx          address  pxGMX address (as secondary reward)
        @param  _name           string   Asset name (e.g. Autocompounding pxGLP)
        @param  _symbol         string   Asset symbol (e.g. apxGLP)
        @param  _platform       address  Platform address (e.g. PirexGmx)
        @param  _rewardsModule  address  Rewards module address
     */
    constructor(
        address _gmxBaseReward,
        address _asset,
        address _pxGmx,
        string memory _name,
        string memory _symbol,
        address _platform,
        address _rewardsModule
    ) PxGmxReward(_pxGmx) PirexERC4626(ERC20(_asset), _name, _symbol) {
        if (_gmxBaseReward == address(0)) revert ZeroAddress();
        if (_asset == address(0)) revert ZeroAddress();
        if (bytes(_name).length == 0) revert InvalidAssetParam();
        if (bytes(_symbol).length == 0) revert InvalidAssetParam();
        if (_platform == address(0)) revert ZeroAddress();
        if (_rewardsModule == address(0)) revert ZeroAddress();

        gmxBaseReward = ERC20(_gmxBaseReward);
        platform = _platform;
        rewardsModule = _rewardsModule;

        // Approve the Uniswap V3 router to manage our base reward (inbound swap token)
        gmxBaseReward.safeApprove(address(_platform), type(uint256).max);
    }

    /**
        @notice Set the withdrawal penalty
        @param  penalty  uint256  Withdrawal penalty
     */
    function setWithdrawalPenalty(uint256 penalty) external onlyOwner {
        if (penalty > MAX_WITHDRAWAL_PENALTY) revert ExceedsMax();

        withdrawalPenalty = penalty;

        emit WithdrawalPenaltyUpdated(penalty);
    }

    /**
        @notice Set the platform fee
        @param  fee  uint256  Platform fee
     */
    function setPlatformFee(uint256 fee) external onlyOwner {
        if (fee > MAX_PLATFORM_FEE) revert ExceedsMax();

        platformFee = fee;

        emit PlatformFeeUpdated(fee);
    }

    /**
        @notice Set the compound incentive
        @param  incentive  uint256  Compound incentive
     */
    function setCompoundIncentive(uint256 incentive) external onlyOwner {
        if (incentive > MAX_COMPOUND_INCENTIVE) revert ExceedsMax();

        compoundIncentive = incentive;

        emit CompoundIncentiveUpdated(incentive);
    }

    /**
        @notice Set the platform
        @param  _platform  address  Platform
     */
    function setPlatform(address _platform) external onlyOwner {
        if (_platform == address(0)) revert ZeroAddress();

        platform = _platform;

        emit PlatformUpdated(_platform);
    }

    /**
        @notice Get the pxGLP custodied by the AutoPxGlp contract
        @return uint256  Amount of pxGLP custodied by the autocompounder
     */
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
        @notice Preview the amount of assets a user would receive from redeeming shares
        @param  shares   uint256  Shares amount
        @return          uint256  Assets amount
     */
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        // Calculate assets based on a user's % ownership of vault shares
        uint256 assets = convertToAssets(shares);

        uint256 _totalSupply = totalSupply;

        // Calculate a penalty - zero if user is the last to withdraw
        uint256 penalty = (_totalSupply == 0 || _totalSupply - shares == 0)
            ? 0
            : assets.mulDivDown(withdrawalPenalty, FEE_DENOMINATOR);

        // Redeemable amount is the post-penalty amount
        return assets - penalty;
    }

    /**
        @notice Preview the amount of shares a user would need to redeem the specified asset amount
        @notice This modified version takes into consideration the withdrawal fee
        @param  assets   uint256  Assets amount
        @return          uint256  Shares amount
     */
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        // Calculate shares based on the specified assets' proportion of the pool
        uint256 shares = convertToShares(assets);

        // Save 1 SLOAD
        uint256 _totalSupply = totalSupply;

        // Factor in additional shares to fulfill withdrawal if user is not the last to withdraw
        return
            (_totalSupply == 0 || _totalSupply - shares == 0)
                ? shares
                : (shares * FEE_DENOMINATOR) /
                    (FEE_DENOMINATOR - withdrawalPenalty);
    }

    /**
        @notice Compound pxGLP (and additionally pxGMX) rewards
        @param  minUsdg                uint256  Minimum USDG amount used when minting GLP
        @param  minGlp                 uint256  Minimum GLP amount received from the WETH deposit
        @param  optOutIncentive        bool     Whether to opt out of the incentive
        @return gmxBaseRewardAmountIn  uint256  WETH inbound amount
        @return pxGmxAmountOut         uint256  pxGMX outbound amount
        @return pxGlpAmountOut         uint256  pxGLP outbound amount
        @return totalPxGlpFee          uint256  Total platform fee for pxGLP
        @return totalPxGmxFee          uint256  Total platform fee for pxGMX
        @return pxGlpIncentive         uint256  Compound incentive for pxGLP
        @return pxGmxIncentive         uint256  Compound incentive for pxGMX
     */
    function compound(
        uint256 minUsdg,
        uint256 minGlp,
        bool optOutIncentive
    )
        public
        returns (
            uint256 gmxBaseRewardAmountIn,
            uint256 pxGmxAmountOut,
            uint256 pxGlpAmountOut,
            uint256 totalPxGlpFee,
            uint256 totalPxGmxFee,
            uint256 pxGlpIncentive,
            uint256 pxGmxIncentive
        )
    {
        if (minUsdg == 0) revert InvalidParam();
        if (minGlp == 0) revert InvalidParam();

        uint256 preClaimTotalAssets = asset.balanceOf(address(this));
        uint256 preClaimPxGmxAmount = pxGmx.balanceOf(address(this));

        PirexRewards(rewardsModule).claim(asset, address(this));
        PirexRewards(rewardsModule).claim(pxGmx, address(this));

        // Track the amount of rewards received
        gmxBaseRewardAmountIn = gmxBaseReward.balanceOf(address(this));

        if (gmxBaseRewardAmountIn != 0) {
            // Deposit received rewards for pxGLP
            (, pxGlpAmountOut, ) = PirexGmx(platform).depositGlp(
                address(gmxBaseReward),
                gmxBaseRewardAmountIn,
                minUsdg,
                minGlp,
                address(this)
            );
        }

        // Distribute fees if the amount of vault assets increased
        uint256 newAssets = totalAssets() - preClaimTotalAssets;
        if (newAssets != 0) {
            totalPxGlpFee = (newAssets * platformFee) / FEE_DENOMINATOR;
            pxGlpIncentive = optOutIncentive
                ? 0
                : (totalPxGlpFee * compoundIncentive) / FEE_DENOMINATOR;

            if (pxGlpIncentive != 0)
                asset.safeTransfer(msg.sender, pxGlpIncentive);

            asset.safeTransfer(owner, totalPxGlpFee - pxGlpIncentive);
        }

        // Track the amount of pxGMX received
        pxGmxAmountOut = pxGmx.balanceOf(address(this)) - preClaimPxGmxAmount;

        if (pxGmxAmountOut != 0) {
            // Calculate and distribute pxGMX fees if the amount of pxGMX increased
            totalPxGmxFee = (pxGmxAmountOut * platformFee) / FEE_DENOMINATOR;
            pxGmxIncentive = optOutIncentive
                ? 0
                : (totalPxGmxFee * compoundIncentive) / FEE_DENOMINATOR;

            if (pxGmxIncentive != 0)
                pxGmx.safeTransfer(msg.sender, pxGmxIncentive);

            pxGmx.safeTransfer(owner, totalPxGmxFee - pxGmxIncentive);

            // Update the pxGmx reward accrual
            _harvest(pxGmxAmountOut - totalPxGmxFee);
        } else {
            // Required to keep the globalState up-to-date
            _globalAccrue();
        }

        emit Compounded(
            msg.sender,
            minGlp,
            gmxBaseRewardAmountIn,
            pxGmxAmountOut,
            pxGlpAmountOut,
            totalPxGlpFee,
            totalPxGmxFee,
            pxGlpIncentive,
            pxGmxIncentive
        );
    }

    /**
        @notice Internal deposit handler
        @param  assets    uint256  pxGLP amount
        @param  receiver  address  apxGLP receiver
        @return shares    uint256  Vault shares (i.e. apxGLP)
     */
    function _deposit(uint256 assets, address receiver)
        internal
        returns (uint256 shares)
    {
        // Check for rounding error since we round down in previewDeposit.
        uint256 supply = totalSupply;

        if (
            (shares = supply == 0
                ? assets
                : assets.mulDivDown(supply, totalAssets() - assets)) == 0
        ) revert ZeroShares();

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(receiver, assets, shares);
    }

    /**
        @notice Deposit fsGLP for apxGLP
        @param  amount    uint256  fsGLP amount
        @param  receiver  address  apxGLP receiver
        @return           uint256  Vault shares (i.e. apxGLP)
     */
    function depositFsGlp(uint256 amount, address receiver)
        external
        nonReentrant
        returns (uint256)
    {
        if (amount == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (totalAssets() != 0) beforeDeposit(address(0), 0, 0);

        ERC20 stakedGlp = ERC20(address(PirexGmx(platform).stakedGlp()));

        // Transfer fsGLP from the caller to the vault
        // before approving PirexGmx to proceed with the deposit
        stakedGlp.safeTransferFrom(msg.sender, address(this), amount);

        // Approve as needed here since the stakedGlp address is mutable in PirexGmx
        stakedGlp.safeApprove(platform, amount);

        (, uint256 assets, ) = PirexGmx(platform).depositFsGlp(
            amount,
            address(this)
        );

        // Handle vault deposit after minting pxGLP
        return _deposit(assets, receiver);
    }

    /**
        @notice Deposit GLP (minted with ERC20 tokens) for apxGLP
        @param  token        address  GMX-whitelisted token for minting GLP
        @param  tokenAmount  uint256  Whitelisted token amount
        @param  minUsdg      uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp       uint256  Minimum GLP amount minted from ERC20 tokens
        @param  receiver     address  apxGLP receiver
        @return              uint256  Vault shares (i.e. apxGLP)
     */
    function depositGlp(
        address token,
        uint256 tokenAmount,
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    ) external nonReentrant returns (uint256) {
        if (token == address(0)) revert ZeroAddress();
        if (tokenAmount == 0) revert ZeroAmount();
        if (minUsdg == 0) revert ZeroAmount();
        if (minGlp == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (totalAssets() != 0) beforeDeposit(address(0), 0, 0);

        // PirexGmx will do the check whether the token is whitelisted or not
        ERC20 erc20Token = ERC20(token);

        // Transfer token from the caller to the vault
        // before approving PirexGmx to proceed with the deposit
        erc20Token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        // Approve as needed here since it can be a new whitelisted token (unless it's the baseReward)
        if (erc20Token != gmxBaseReward) {
            erc20Token.safeApprove(platform, tokenAmount);
        }

        (, uint256 assets, ) = PirexGmx(platform).depositGlp(
            token,
            tokenAmount,
            minUsdg,
            minGlp,
            address(this)
        );

        // Handle vault deposit after minting pxGLP
        return _deposit(assets, receiver);
    }

    /**
        @notice Deposit GLP (minted with ETH) for apxGLP
        @param  minUsdg   uint256  Minimum USDG purchased and used to mint GLP
        @param  minGlp    uint256  Minimum GLP amount minted from ETH
        @param  receiver  address  apxGLP receiver
        @return           uint256  Vault shares (i.e. apxGLP)
     */
    function depositGlpETH(
        uint256 minUsdg,
        uint256 minGlp,
        address receiver
    ) external payable nonReentrant returns (uint256) {
        if (msg.value == 0) revert ZeroAmount();
        if (minUsdg == 0) revert ZeroAmount();
        if (minGlp == 0) revert ZeroAmount();
        if (receiver == address(0)) revert ZeroAddress();

        if (totalAssets() != 0) beforeDeposit(address(0), 0, 0);

        (, uint256 assets, ) = PirexGmx(platform).depositGlpETH{
            value: msg.value
        }(minUsdg, minGlp, address(this));

        // Handle vault deposit after minting pxGLP
        return _deposit(assets, receiver);
    }

    /**
        @notice Override the withdrawal method to make sure compound is called before withdrawing
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        compound(1, 1, true);

        shares = PirexERC4626.withdraw(assets, receiver, owner);
    }

    /**
        @notice Override the redemption method to make sure compound is called before redeeming
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        compound(1, 1, true);

        assets = PirexERC4626.redeem(shares, receiver, owner);
    }

    /**
        @notice Compound and internally update pxGMX reward accrual before deposit
     */
    function beforeDeposit(
        address,
        uint256,
        uint256
    ) internal override {
        compound(1, 1, true);
    }

    /**
        @notice Update pxGMX reward accrual after deposit
        @param  receiver  address  Receiver of the vault shares
     */
    function afterDeposit(
        address receiver,
        uint256,
        uint256
    ) internal override {
        _globalAccrue();
        _userAccrue(receiver);
    }

    /**
        @notice Update pxGMX reward accrual after withdrawal
        @param  owner  address  Owner of the vault shares
     */
    function afterWithdraw(
        address owner,
        uint256,
        uint256
    ) internal override {
        _globalAccrue();
        _userAccrue(owner);
    }

    /**
        @notice Update pxGMX reward accrual for both sender and receiver after transfer
        @param  owner     address  Owner of the vault shares
        @param  receiver  address  Receiver of the vault shares
     */
    function afterTransfer(
        address owner,
        address receiver,
        uint256
    ) internal override {
        _userAccrue(owner);
        _userAccrue(receiver);
    }
}
