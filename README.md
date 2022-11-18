# Redacted Cartel contest details
- Total Prize Pool: $90,500 USDC
  - HM awards: $63,750 USDC
  - QA report awards: $7,500 USDC
  - Gas report awards: $3,750 USDC
  - Judge + presort awards: $15,000 USDC
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2022-11-redacted-cartel-contest/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts November 21, 2022 20:00 UTC
- Ends November 28, 2022 20:00 UTC

## C4udit / Publicly Known Issues

The C4audit output for the contest can be found [here](add link to report) within an hour of contest opening.

*Note for C4 wardens: Anything included in the C4udit output is considered a publicly known issue and is ineligible for awards.*

# Overview

Pirex provides GMX token holders with a streamlined and convenient solution for maximizing the productivity of their GMX and GLP tokens. As a user of Pirex, you can benefit in the following ways:

- Boosted yield as a result of frequent and continuous multiplier point compounding
- Efficient, autonomous compounding of rewards into pxGMX or pxGLP (if using "Easy Mode")
- Mint tokens backed by your future GMX rewards and sell them on our decentralized futures marketplace (if using "Hard Mode" - coming soon)

And more. We're continuously improving our products and adding value to our users, and will make announcements as additional utility is available for our tokens. Please follow us on Twitter ([@redactedcartel](https://twitter.com/redactedcartel)) to stay in the loop ❤️.

### How Does It Work?

**_Tokens_**

pxGMX: The Pirex-wrapped version of staked GMX and \*esGMX, handled in a way to maximize yield for the protocol's users (e.g. continuous, automatic, socialized multiplier point compounding). pxGMX token holders will be able to claim rewards and vote in GMX governance proposals (coming soon, after launch), just as they would with staked GMX. pxGMX cannot be redeemed for the underlying assets (those assets are essentially "blackholed" and will never resurface on the market), but can be sold for GMX, via a liquidity pool which we will seed (i.e. add initial pxGMX and GMX liquidity).

\*esGMX rewards are distributed as pxGMX, which are minted at the time of an individual user's reward claim. When unclaimed/unminted, the rewards earned by esGMX-backed pxGMX will be distributed amongst existing pxGMX token holders, boosting their rewards even further!

pxGLP: The Pirex-wrapped version of staked GLP, handled in the same way as pxGMX to maximize yield. pxGLP token holders can claim rewards, just as they would with staked GLP, and also redeem them for any GLP constituent asset ([check the GMX app for a complete list](https://app.gmx.io/#/buy_glp#redeem)).

**_Modes_**

Easy Mode: Sit back, relax, and we will autocompound the pxGMX and pxGLP rewards into more of those assets for you.

Standard Mode: Manually handle your pxGMX or pxGLP by claiming rewards and other actions (e.g. vote in GMX governance with pxGMX), while still enjoying the benefits of Pirex-GMX's multiplier point auto-compounding.

Hard Mode (Coming Soon): Stake your pxGMX or pxGLP and mint tokens representing their future rewards (e.g. you can stake pxGMX for 1 year and receive the equivalent of 1 year's worth of rewards - after 1 year, you can unstake your pxGMX), and sell it on our decentralized futures marketplace.

### Core Contract Overview

**PirexGmx.sol**

- Intakes GMX-based tokens (GMX and GLP) and mints their synthetic counterparts in return (pxGMX and pxGLP)
- Allows users to redeem their pxGLP for GLP constituent assets (same assets which GMX allows GLP to be traded for, e.g. USDC, WBTC, etc.)
- Interacts with the GMX contracts to stake and mint assets, claim rewards, perform asset migrations (only if necessary, as a result of a contract upgrade), and more
- Custodies GMX rewards until they are claimed and distributed via a call from the PirexRewards contract

**PirexRewards.sol**

- Tracks perpetually accrued/continuously streamed GMX rewards across multiple scopes: global, different reward tokens, and individual users
- Has permission to call various reward-related methods on the PirexGmx contract for claiming and distributing rewards to users
- Enables reward forwarding, and can also set a reward recipient on behalf of contract accounts (permissioned, used to direct rewards accrued from tokens in LP contracts - those rewards would otherwise be wasted)

**PirexFees.sol**

- Custodies protocol fees and distributes them to the Redacted treasury and Pirex contributor multisig
- Allows its owner, a Redacted multisig, to modify various contract state variables (i.e. fee percent and fee recipient addresses)

**PxERC20.sol**

- Modifies standard ERC20 methods with calls to PirexRewards's reward accrual methods to ensure that asset ownership and reward distribution can be properly accounted for

**PxGmx.sol**

- Is a derivative of the PxERC20 contract
- Represents GMX and esGMX tokens (calls the PxERC20 constructor, which it is derived from, with fixed values that is consistent with this goal)
- Overwrites the `burn` method of PxERC20 (pxGMX cannot be redeemed for GMX or esGMX)

**AutoPxGmx.sol**

- Accepts GMX\* and pxGMX deposits, and issues share tokens (apxGMX) against them
- Compounds pxGMX rewards into more pxGMX: Swaps WETH rewards into GMX via Uniswap V3 and deposits it into PirexGmx to acquire pxGMX, and claims/mints esGMX-backed pxGMX rewards
- Provides a series of permissioned methods that enables the Pirex multisig to configure fees, incentives, and Uniswap V3 pool fee

\*NOTE: GMX is converted into pxGMX.

**AutoPxGlp.sol**

- Accepts GLP, GLP constituent assets, and pxGLP deposits, and issues share tokens (apxGLP) against them
- Compounds pxGLP WETH rewards into more pxGLP, and tracks esGMX-backed pxGMX rewards earned by vault users
- Provides a series of permissioned methods that enables the Pirex multisig to configure fees, incentives, and Uniswap V3 pool fee

### Contract Diagram

Below are visualizations of how Pirex-GMX contracts interact with one another as well as with external contracts (e.g. GMX's contracts) as a result of different user interactions. Please note that the diagrams do not cover every single user action for the purpose of avoiding redundancy (e.g. the diagram for depositing GMX and acquiring pxGMX is more or less the same as depositing GLP or GLP constituent assets and acquiring pxGLP).

### Contract Diagram: Deposit GMX, Receive pxGMX

![Contract Diagram: Deposit GMX, Receive pxGMX](https://i.imgur.com/5qEKj8q.png)

### Contract Diagram: Claim pxGMX/pxGLP Rewards

![Contract Diagram: Claim pxGMX/pxGLP Rewards](https://i.imgur.com/NqaxI2P.png)

### Contract Diagram: Auto-compound pxGMX Rewards

![Contract Diagram: Auto-compound pxGMX Rewards](https://i.imgur.com/raWbR1z.png)

# Scope

| Contract | SLOC | Purpose | Libraries used |
| ----------- | ----------- | ----------- | ----------- |
| src/Common.sol | 11 | Shared struct types | None |
| src/PirexFees.sol | 67 | Distributes protocol fees to treasury and contributors | [`solmate/*`](<(https://github.com/transmissions11/solmate)>) |
| src/PirexGmx.sol | 645 | Handles and custodies GMX assets on behalf of users | [`solmate/*`](<(https://github.com/transmissions11/solmate)>), [`openzeppelin-contracts/*`](<(https://github.com/OpenZeppelin/openzeppelin-contracts)>) |
| src/PirexRewards.sol | 303 | Maintains Pirex-GMX tokens' reward-related state | [`solmate/*`](<(https://github.com/transmissions11/solmate)>), [`openzeppelin-contracts-upgradeable/*`](<(https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable)>) |
| src/PxERC20.sol | 76 | Pirex-GMX token with hooks for reward accounting upon supply and balance changes | [`solmate/*`](<(https://github.com/transmissions11/solmate)>), [`openzeppelin-contracts/*`](<(https://github.com/OpenZeppelin/openzeppelin-contracts)>) |
| src/PxGmx.sol | 12 | PxERC20 but with the fixed pxGMX-related values and the `burn` method overriden | [`solmate/*`](<(https://github.com/transmissions11/solmate)>), [`openzeppelin-contracts/*`](<(https://github.com/OpenZeppelin/openzeppelin-contracts)>) |
| src/interfaces/IAutoPxGlp.sol | 18 | AutoPxGlp interface | None |
| src/interfaces/IPirexRewards.sol | 11 | PirexRewards interface | None |
| src/interfaces/IProducer.sol | 16 | Producer/PirexGmx interface | None |
| src/vaults/AutoPxGlp.sol | 302 | pxGLP auto-compounding vault | [`solmate/*`](<(https://github.com/transmissions11/solmate)>) |
| src/vaults/AutoPxGmx.sol | 250 | pxGMX auto-compounding vault | [`solmate/*`](<(https://github.com/transmissions11/solmate)>) |
| src/vaults/PirexERC4626.sol | 190 | Modified Solmate ERC-4626 contract | [`solmate/*`](<(https://github.com/transmissions11/solmate)>) |
| src/vaults/PxGmxReward.sol | 80 | Maintains esGMX-backed pxGMX reward state for AutoPxGlp | [`solmate/*`](<(https://github.com/transmissions11/solmate)>) |

## Out of scope

Please note that we will not be acknowledging nor awarding "centralization risk" findings related to the contract owner (a Redacted-Pirex multisig) being able to call certain permissioned methods - some of which may jeopardize user funds safety if called with malicious intent. While we do recognize the risk, we also believe that certain privileges need to be retained by our team in order to safeguard user funds and maintain the protocol's continued operations - for example, should our contracts become incompatible with GMX's at any point (as a result of them updating their contracts), we would need to perform a full account transfer of the GMX assets to an updated version of our contract that is compatible. That said, we are taking steps to mitigate risks to users, the first of which is the utilization of a Gnosis Safe multisig in conjunction with Metropolis (previously, known as Orca), which provides us with more granular control over signature thresholds and signers (this would enable us to carry out precautionary measures such as requiring a greater # of trustworthy signers for executing higher risk, privileged actions).

Thank you for understanding!

## Scope + Test Coverage
### Files in scope
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|[Coverage](#nowhere "(Lines hit / Total)")|
|:-|:-:|:-:|
|_Contracts (8)_|
|[src/PxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PxGmx.sol)|[12](#nowhere "(nSLOC:8, SLOC:12, Lines:24)")|-|
|[src/PirexFees.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexFees.sol)|[67](#nowhere "(nSLOC:61, SLOC:67, Lines:117)")|[100.00%](#nowhere "(Hit:16 / Total:16)")|
|[src/PxERC20.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PxERC20.sol) [🧮](#nowhere "Uses Hash-Functions") [Σ](#nowhere "Unchecked Blocks")|[74](#nowhere "(nSLOC:58, SLOC:74, Lines:134)")|[100.00%](#nowhere "(Hit:21 / Total:21)")|
|[src/vaults/PxGmxReward.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PxGmxReward.sol)|[80](#nowhere "(nSLOC:80, SLOC:80, Lines:134)")|[78.13%](#nowhere "(Hit:25 / Total:32)")|
|[src/vaults/AutoPxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGmx.sol)|[250](#nowhere "(nSLOC:210, SLOC:250, Lines:404)")|[89.39%](#nowhere "(Hit:59 / Total:66)")|
|[src/vaults/AutoPxGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGlp.sol) [💰](#nowhere "Payable Functions")|[302](#nowhere "(nSLOC:236, SLOC:302, Lines:509)")|[91.11%](#nowhere "(Hit:82 / Total:90)")|
|[src/PirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexRewards.sol)|[303](#nowhere "(nSLOC:253, SLOC:303, Lines:480)")|[98.98%](#nowhere "(Hit:97 / Total:98)")|
|[src/PirexGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexGmx.sol) [💰](#nowhere "Payable Functions")|[645](#nowhere "(nSLOC:512, SLOC:645, Lines:974)")|[100.00%](#nowhere "(Hit:172 / Total:172)")|
|_Abstracts (1)_|
|[src/vaults/PirexERC4626.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PirexERC4626.sol) [📤](#nowhere "Initiates ETH Value Transfer")|[190](#nowhere "(nSLOC:121, SLOC:190, Lines:301)")|[75.00%](#nowhere "(Hit:39 / Total:52)")|
|_Interfaces (3)_|
|[src/interfaces/IPirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IPirexRewards.sol)|[11](#nowhere "(nSLOC:5, SLOC:11, Lines:14)")|-|
|[src/interfaces/IProducer.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IProducer.sol)|[16](#nowhere "(nSLOC:6, SLOC:16, Lines:20)")|-|
|[src/interfaces/IAutoPxGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IAutoPxGlp.sol)|[18](#nowhere "(nSLOC:4, SLOC:18, Lines:20)")|-|
|_Structs (1)_|
|[src/Common.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/Common.sol)|[11](#nowhere "(nSLOC:11, SLOC:11, Lines:14)")|-|
|Total (over 13 files):| [1979](#nowhere "(nSLOC:1565, SLOC:1979, Lines:3145)")| [93.42%](#nowhere "Hit:511 / Total:547")|


### All other source contracts (not in scope)
|File|[SLOC](#nowhere "(nSLOC, SLOC, Lines)")|[Coverage](#nowhere "(Lines hit / Total)")|
|:-|:-:|:-:|
|_Contracts (2)_|
|[src/external/DelegateRegistry.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/external/DelegateRegistry.sol)|[23](#nowhere "(nSLOC:23, SLOC:23, Lines:46)")|[91.67%](#nowhere "(Hit:11 / Total:12)")|
|[src/external/RewardTracker.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/external/RewardTracker.sol) [🖥](#nowhere "Uses Assembly") [👥](#nowhere "DelegateCall")|[747](#nowhere "(nSLOC:539, SLOC:747, Lines:1240)")|[0.00%](#nowhere "(Hit:0 / Total:170)")|
|_Interfaces (11)_|
|[src/interfaces/IRewardDistributor.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IRewardDistributor.sol)|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:6)")|-|
|[src/interfaces/IWETH.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IWETH.sol) [💰](#nowhere "Payable Functions")|[4](#nowhere "(nSLOC:4, SLOC:4, Lines:7)")|-|
|[src/interfaces/IGlpManager.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IGlpManager.sol)|[6](#nowhere "(nSLOC:6, SLOC:6, Lines:11)")|-|
|[src/interfaces/ITimelock.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/ITimelock.sol)|[7](#nowhere "(nSLOC:7, SLOC:7, Lines:13)")|-|
|[src/interfaces/IBasePositionManager.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IBasePositionManager.sol)|[8](#nowhere "(nSLOC:5, SLOC:8, Lines:11)")|-|
|[src/interfaces/IStakedGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IStakedGlp.sol)|[9](#nowhere "(nSLOC:5, SLOC:9, Lines:14)")|-|
|[src/interfaces/IGMX.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IGMX.sol)|[11](#nowhere "(nSLOC:8, SLOC:11, Lines:18)")|-|
|[src/interfaces/IVaultPriceFeed.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IVaultPriceFeed.sol)|[41](#nowhere "(nSLOC:18, SLOC:41, Lines:57)")|-|
|[src/interfaces/IRewardRouterV2.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IRewardRouterV2.sol) [💰](#nowhere "Payable Functions")|[47](#nowhere "(nSLOC:22, SLOC:47, Lines:68)")|-|
|[src/interfaces/IV3SwapRouter.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IV3SwapRouter.sol) [💰](#nowhere "Payable Functions")|[50](#nowhere "(nSLOC:38, SLOC:50, Lines:80)")|-|
|[src/interfaces/IVault.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IVault.sol)|[261](#nowhere "(nSLOC:99, SLOC:261, Lines:357)")|-|
|Total (over 13 files):| [1218](#nowhere "(nSLOC:778, SLOC:1218, Lines:1928)")| [6.04%](#nowhere "Hit:11 / Total:182")|

## External imports
* **openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol**
  * [src/PirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexRewards.sol)
* **openzeppelin-contracts/contracts/access/AccessControl.sol**
  * [src/PxERC20.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PxERC20.sol)
* **openzeppelin-contracts/contracts/security/Pausable.sol**
  * [src/PirexGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexGmx.sol)
* **solmate/auth/Owned.sol**
  * [src/PirexFees.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexFees.sol)
  * [src/PirexGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexGmx.sol)
  * [src/vaults/AutoPxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGmx.sol)
  * [src/vaults/PxGmxReward.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PxGmxReward.sol)
* **solmate/tokens/ERC20.sol**
  * [src/PirexFees.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexFees.sol)
  * [src/PirexGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexGmx.sol)
  * [src/PirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexRewards.sol)
  * [src/PxERC20.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PxERC20.sol)
  * [src/interfaces/IPirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IPirexRewards.sol)
  * [src/interfaces/IProducer.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IProducer.sol)
  * [src/vaults/AutoPxGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGlp.sol)
  * [src/vaults/AutoPxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGmx.sol)
  * [src/vaults/PirexERC4626.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PirexERC4626.sol)
  * [src/vaults/PxGmxReward.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PxGmxReward.sol)
* **solmate/utils/FixedPointMathLib.sol**
  * [src/vaults/AutoPxGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGlp.sol)
  * [src/vaults/AutoPxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGmx.sol)
  * [src/vaults/PirexERC4626.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PirexERC4626.sol)
* **solmate/utils/ReentrancyGuard.sol**
  * [src/PirexGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexGmx.sol)
  * [src/vaults/AutoPxGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGlp.sol)
  * [src/vaults/AutoPxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGmx.sol)
* **solmate/utils/SafeCastLib.sol**
  * [src/PirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexRewards.sol)
  * [src/vaults/PxGmxReward.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PxGmxReward.sol)
* **solmate/utils/SafeTransferLib.sol**
  * [src/PirexFees.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexFees.sol)
  * [src/PirexGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexGmx.sol)
  * [src/PirexRewards.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/PirexRewards.sol)
  * [src/vaults/AutoPxGlp.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGlp.sol)
  * [src/vaults/AutoPxGmx.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGmx.sol)
  * [src/vaults/PirexERC4626.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PirexERC4626.sol)
  * [src/vaults/PxGmxReward.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/vaults/PxGmxReward.sol)
/2022-11-redactedcartel/blob/main/src/vaults/AutoPxGlp.sol)
* **v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol**
  * ~~[src/interfaces/IV3SwapRouter.sol](https://github.com/code-423n4/2022-11-redactedcartel/blob/main/src/interfaces/IV3SwapRouter.sol)~~

# Additional Context

N/A

## Scoping Details
```
- If you have a public code repo, please share it here: https://github.com/redacted-cartel/pirex-gmx
- How many contracts are in scope?  13
- Total SLoC for these contracts? 1981
- How many external imports are there? 17
- How many separate interfaces and struct definitions are there for the contracts within scope? 3 interfaces, 3 structs
- Does most of your code generally use composition or inheritance? Inheritance to keep code lean and for security purposes (i.e. use code that has been previously audited and broadly casted)
- How many external calls?  Strictly only calls to contracts that are *not* ours (e.g. `asset.balanceOf(address)` calls in ERC-4626 vaults are not included, since those are all px assets): 54
- What is the overall line coverage percentage provided by your tests?  Using Forge's coverage command (for these contracts only: PirexFees.sol, PirexGmx.sol, PirexRewards.sol, PxERC20.sol, PxGmx.sol, AutoPxGlp.sol, AutoPxGmx.sol, PxGmxReward.sol): 98.26875%
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol? Yes
- Please describe required context: https://gist.github.com/kphed/27920e52ef59ecb88516fefa4bd2337b
- Does it use an oracle? No
- Does the token conform to the ERC20 standard? Yes
- Are there any novel or unique curve logic or mathematical models? No
- Does it use a timelock function? No
- Is it an NFT? No
- Does it have an AMM? No
- Is it a fork or alternate implementation of another project? Yes
- If yes, please describe your customisations:  This protocol is a variant of our Pirex-Convex protocol which can be viewed here: https://pirex.io
- Does it use rollups? Yes
- Is it multi-chain? Yes
- Does it use a side-chain? Yes
- If yes, is the sidechain evm-compatible? Yes, Avalanche
```

# Tests

IDE: VSCode 1.73.0 (Universal)

Forge: 0.2.0

From inside the project directory:

1. Install contract dependencies `forge i`
2. Compile contracts `forge build`
3. Set up and run tests
   - Create the test variables helper script `cp scripts/loadEnv.example.sh scripts/loadEnv.sh`
   - Define the values within the newly-created file*
   - Run the test helper script `scripts/forgeTest.sh` (along with any `forge test` arguments, flags, options, etc.)

*NOTE: Please use either an Arbitrum or Avalanche RPC endpoint. If using the latter, exclude tests for the AutoPxGmx contract with this appended when running the test helper script: `--no-match-contract AutoPxGmx` - the pxGMX vault needs to be updated to support WAVAX => GMX swaps on TraderJoe.
