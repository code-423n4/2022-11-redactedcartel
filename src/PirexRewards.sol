// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IProducer} from "src/interfaces/IProducer.sol";
import {GlobalState, UserState} from "src/Common.sol";

/**
    Originally inspired by Flywheel V2 (thank you Tribe team):
    https://github.com/fei-protocol/flywheel-v2/blob/dbe3cb8/src/FlywheelCore.sol
*/
contract PirexRewards is OwnableUpgradeable {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    struct ProducerToken {
        ERC20[] rewardTokens;
        GlobalState globalState;
        mapping(address => UserState) userStates;
        mapping(ERC20 => uint256) rewardStates;
        mapping(address => mapping(ERC20 => address)) rewardRecipients;
    }

    // Pirex contract which produces rewards
    IProducer public producer;

    // Producer tokens mapped to their data
    mapping(ERC20 => ProducerToken) public producerTokens;

    event SetProducer(address producer);
    event SetRewardRecipient(
        address indexed user,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken,
        address recipient
    );
    event UnsetRewardRecipient(
        address indexed user,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event AddRewardToken(
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );
    event RemoveRewardToken(ERC20 indexed producerToken, uint256 removalIndex);
    event GlobalAccrue(
        ERC20 indexed producerToken,
        uint256 lastUpdate,
        uint256 lastSupply,
        uint256 rewards
    );
    event UserAccrue(
        ERC20 indexed producerToken,
        address indexed user,
        uint256 lastUpdate,
        uint256 lastBalance,
        uint256 rewards
    );
    event Harvest(
        ERC20[] producerTokens,
        ERC20[] rewardTokens,
        uint256[] rewardAmounts
    );
    event Claim(ERC20 indexed producerToken, address indexed user);
    event SetRewardRecipientPrivileged(
        address indexed lpContract,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken,
        address recipient
    );
    event UnsetRewardRecipientPrivileged(
        address indexed lpContract,
        ERC20 indexed producerToken,
        ERC20 indexed rewardToken
    );

    error ZeroAddress();
    error NotContract();
    error TokenAlreadyAdded();

    function initialize() public initializer {
        __Ownable_init();
    }

    /**
        @notice Set producer
        @param  _producer  address  Producer contract address
     */
    function setProducer(address _producer) external onlyOwner {
        if (_producer == address(0)) revert ZeroAddress();

        producer = IProducer(_producer);

        emit SetProducer(_producer);
    }

    /**
        @notice Set reward recipient for a reward token
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @param  recipient      address  Rewards recipient
    */
    function setRewardRecipient(
        ERC20 producerToken,
        ERC20 rewardToken,
        address recipient
    ) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        producerTokens[producerToken].rewardRecipients[msg.sender][
            rewardToken
        ] = recipient;

        emit SetRewardRecipient(
            msg.sender,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Unset reward recipient for a reward token
        @param  producerToken  ERC20  Producer token contract
        @param  rewardToken    ERC20  Reward token contract
    */
    function unsetRewardRecipient(ERC20 producerToken, ERC20 rewardToken)
        external
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete producerTokens[producerToken].rewardRecipients[msg.sender][
            rewardToken
        ];

        emit UnsetRewardRecipient(msg.sender, producerToken, rewardToken);
    }

    /**
        @notice Add a reward token to a producer token's rewardTokens array
        @param  producerToken  ERC20  Producer token contract
        @param  rewardToken    ERC20  Reward token contract
    */
    function addRewardToken(ERC20 producerToken, ERC20 rewardToken)
        external
        onlyOwner
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        // Check if the token has been added previously for the specified producer
        ProducerToken storage p = producerTokens[producerToken];
        ERC20[] memory rewardTokens = p.rewardTokens;
        uint256 len = rewardTokens.length;

        for (uint256 i; i < len; ++i) {
            if (address(rewardTokens[i]) == address(rewardToken)) {
                revert TokenAlreadyAdded();
            }
        }

        p.rewardTokens.push(rewardToken);

        emit AddRewardToken(producerToken, rewardToken);
    }

    /**
        @notice Remove a reward token from a producer token's rewardTokens array
        @param  producerToken  ERC20    Producer token contract
        @param  removalIndex   uint256  Index of the element to be removed
    */
    function removeRewardToken(ERC20 producerToken, uint256 removalIndex)
        external
        onlyOwner
    {
        if (address(producerToken) == address(0)) revert ZeroAddress();

        ERC20[] storage rewardTokens = producerTokens[producerToken]
            .rewardTokens;
        uint256 lastIndex = rewardTokens.length - 1;

        if (removalIndex != lastIndex) {
            // Set the element at removalIndex to the last element
            rewardTokens[removalIndex] = rewardTokens[lastIndex];
        }

        rewardTokens.pop();

        emit RemoveRewardToken(producerToken, removalIndex);
    }

    /**
        @notice Getter for a producer token's UserState struct member values
        @param  producerToken  ERC20    Producer token contract
        @param  user           address  User
        @return lastUpdate     uint256  Last update
        @return lastBalance    uint256  Last balance
        @return rewards        uint256  Rewards
    */
    function getUserState(ERC20 producerToken, address user)
        external
        view
        returns (
            uint256 lastUpdate,
            uint256 lastBalance,
            uint256 rewards
        )
    {
        UserState memory userState = producerTokens[producerToken].userStates[
            user
        ];

        return (userState.lastUpdate, userState.lastBalance, userState.rewards);
    }

    /**
        @notice Getter for a producer token's accrued amount for a reward token
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @return                uint256  Reward state
    */
    function getRewardState(ERC20 producerToken, ERC20 rewardToken)
        external
        view
        returns (uint256)
    {
        return producerTokens[producerToken].rewardStates[rewardToken];
    }

    /**
        @notice Getter for a producer token's reward tokens
        @param  producerToken  ERC20    Producer token contract
        @return                ERC20[]  Reward token contracts
    */
    function getRewardTokens(ERC20 producerToken)
        external
        view
        returns (ERC20[] memory)
    {
        return producerTokens[producerToken].rewardTokens;
    }

    /**
        @notice Get the reward recipient for a user by producer and reward token
        @param  user           address  User
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @return                address  Reward recipient
    */
    function getRewardRecipient(
        address user,
        ERC20 producerToken,
        ERC20 rewardToken
    ) external view returns (address) {
        return
            producerTokens[producerToken].rewardRecipients[user][rewardToken];
    }

    /**
        @notice Update global rewards accrual state
        @param  producerToken  ERC20  Rewards-producing token
    */
    function globalAccrue(ERC20 producerToken) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();

        _globalAccrue(producerTokens[producerToken].globalState, producerToken);
    }

    /**
        @notice Update user rewards accrual state
        @param  producerToken  ERC20    Rewards-producing token
        @param  user           address  User address
    */
    function userAccrue(ERC20 producerToken, address user) public {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        UserState storage u = producerTokens[producerToken].userStates[user];
        uint256 balance = producerToken.balanceOf(user);

        // Calculate the amount of rewards accrued by the user up to this call
        uint256 rewards = u.rewards +
            u.lastBalance *
            (block.timestamp - u.lastUpdate);

        u.lastUpdate = block.timestamp.safeCastTo32();
        u.lastBalance = balance.safeCastTo224();
        u.rewards = rewards;

        emit UserAccrue(producerToken, user, block.timestamp, balance, rewards);
    }

    /**
        @notice Update global accrual state
        @param  globalState    GlobalState  Global state of the producer token
        @param  producerToken  ERC20        Producer token contract
    */
    function _globalAccrue(GlobalState storage globalState, ERC20 producerToken)
        internal
    {
        uint256 totalSupply = producerToken.totalSupply();
        uint256 lastUpdate = globalState.lastUpdate;
        uint256 lastSupply = globalState.lastSupply;

        // Calculate rewards, the product of seconds elapsed and last supply
        // Only calculate and update states when needed
        if (block.timestamp != lastUpdate || totalSupply != lastSupply) {
            uint256 rewards = globalState.rewards +
                (block.timestamp - lastUpdate) *
                lastSupply;

            globalState.lastUpdate = block.timestamp.safeCastTo32();
            globalState.lastSupply = totalSupply.safeCastTo224();
            globalState.rewards = rewards;

            emit GlobalAccrue(
                producerToken,
                block.timestamp,
                totalSupply,
                rewards
            );
        }
    }

    /**
        @notice Harvest rewards
        @return _producerTokens  ERC20[]  Producer token contracts
        @return rewardTokens     ERC20[]  Reward token contracts
        @return rewardAmounts    ERC20[]  Reward token amounts
    */
    function harvest()
        public
        returns (
            ERC20[] memory _producerTokens,
            ERC20[] memory rewardTokens,
            uint256[] memory rewardAmounts
        )
    {
        (_producerTokens, rewardTokens, rewardAmounts) = producer
            .claimRewards();
        uint256 pLen = _producerTokens.length;

        // Iterate over the producer tokens and update reward state
        for (uint256 i; i < pLen; ++i) {
            ERC20 p = _producerTokens[i];
            uint256 r = rewardAmounts[i];

            // Update global reward accrual state and associate with the update of reward state
            ProducerToken storage producerState = producerTokens[p];

            _globalAccrue(producerState.globalState, p);

            if (r != 0) {
                producerState.rewardStates[rewardTokens[i]] += r;
            }
        }

        emit Harvest(_producerTokens, rewardTokens, rewardAmounts);
    }

    /**
        @notice Claim rewards
        @param  producerToken  ERC20    Producer token contract
        @param  user           address  User
    */
    function claim(ERC20 producerToken, address user) external {
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (user == address(0)) revert ZeroAddress();

        harvest();
        userAccrue(producerToken, user);

        ProducerToken storage p = producerTokens[producerToken];
        uint256 globalRewards = p.globalState.rewards;
        uint256 userRewards = p.userStates[user].rewards;

        // Claim should be skipped and not reverted on zero global/user reward
        if (globalRewards != 0 && userRewards != 0) {
            ERC20[] memory rewardTokens = p.rewardTokens;
            uint256 rLen = rewardTokens.length;

            // Update global and user reward states to reflect the claim
            p.globalState.rewards = globalRewards - userRewards;
            p.userStates[user].rewards = 0;

            emit Claim(producerToken, user);

            // Transfer the proportionate reward token amounts to the recipient
            for (uint256 i; i < rLen; ++i) {
                ERC20 rewardToken = rewardTokens[i];
                address rewardRecipient = p.rewardRecipients[user][rewardToken];
                address recipient = rewardRecipient != address(0)
                    ? rewardRecipient
                    : user;
                uint256 rewardState = p.rewardStates[rewardToken];
                uint256 amount = (rewardState * userRewards) / globalRewards;

                if (amount != 0) {
                    // Update reward state (i.e. amount) to reflect reward tokens transferred out
                    p.rewardStates[rewardToken] = rewardState - amount;

                    producer.claimUserReward(
                        address(rewardToken),
                        amount,
                        recipient
                    );
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    ⚠️ NOTABLE PRIVILEGED METHODS ⚠️
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Privileged method for setting the reward recipient of a contract
        @notice This should ONLY be used to forward rewards for Pirex-GMX LP contracts
        @notice In production, we will have a 2nd multisig which reduces risk of abuse
        @param  lpContract     address  Pirex-GMX LP contract
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
        @param  recipient      address  Rewards recipient
    */
    function setRewardRecipientPrivileged(
        address lpContract,
        ERC20 producerToken,
        ERC20 rewardToken,
        address recipient
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();
        if (recipient == address(0)) revert ZeroAddress();

        producerTokens[producerToken].rewardRecipients[lpContract][
            rewardToken
        ] = recipient;

        emit SetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken,
            recipient
        );
    }

    /**
        @notice Privileged method for unsetting the reward recipient of a contract
        @param  lpContract     address  Pirex-GMX LP contract
        @param  producerToken  ERC20    Producer token contract
        @param  rewardToken    ERC20    Reward token contract
    */
    function unsetRewardRecipientPrivileged(
        address lpContract,
        ERC20 producerToken,
        ERC20 rewardToken
    ) external onlyOwner {
        if (lpContract.code.length == 0) revert NotContract();
        if (address(producerToken) == address(0)) revert ZeroAddress();
        if (address(rewardToken) == address(0)) revert ZeroAddress();

        delete producerTokens[producerToken].rewardRecipients[lpContract][
            rewardToken
        ];

        emit UnsetRewardRecipientPrivileged(
            lpContract,
            producerToken,
            rewardToken
        );
    }
}
