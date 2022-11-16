// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IAutoPxGlp} from "src/interfaces/IAutoPxGlp.sol";
import {GlobalState, UserState} from "src/Common.sol";

contract PxGmxReward is Owned {
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    ERC20 public pxGmx;

    GlobalState public globalState;
    uint256 public rewardState;
    mapping(address => UserState) public userRewardStates;

    event GlobalAccrue(uint256 lastUpdate, uint256 lastSupply, uint256 rewards);
    event UserAccrue(
        address indexed user,
        uint256 lastUpdate,
        uint256 lastSupply,
        uint256 rewards
    );
    event Harvest(uint256 rewardAmount);
    event PxGmxClaimed(
        address indexed account,
        address receiver,
        uint256 amount
    );

    error ZeroAddress();

    /**
        @param  _pxGmx  address  pxGMX token address
     */
    constructor(address _pxGmx) Owned(msg.sender) {
        if (_pxGmx == address(0)) revert ZeroAddress();

        pxGmx = ERC20(_pxGmx);
    }

    /**
        @notice Update global rewards accrual state
    */
    function _globalAccrue() internal {
        uint256 totalSupply = ERC20(address(this)).totalSupply();

        // Calculate rewards, the product of seconds elapsed and last supply
        uint256 rewards = globalState.rewards +
            (block.timestamp - globalState.lastUpdate) *
            globalState.lastSupply;

        globalState.lastUpdate = block.timestamp.safeCastTo32();
        globalState.lastSupply = totalSupply.safeCastTo224();
        globalState.rewards = rewards;

        emit GlobalAccrue(block.timestamp, totalSupply, rewards);
    }

    /**
        @notice Update user rewards accrual state
        @param  user  address  User address
    */
    function _userAccrue(address user) internal {
        if (user == address(0)) revert ZeroAddress();

        UserState storage u = userRewardStates[user];
        uint256 balance = ERC20(address(this)).balanceOf(user);

        // Calculate the amount of rewards accrued by the user up to this call
        uint256 rewards = u.rewards +
            u.lastBalance *
            (block.timestamp - u.lastUpdate);

        u.lastUpdate = block.timestamp.safeCastTo32();
        u.lastBalance = balance.safeCastTo224();
        u.rewards = rewards;

        emit UserAccrue(user, block.timestamp, balance, rewards);
    }

    /**
        @notice Harvest rewards
        @param  rewardAmount  uint256  Reward token amount
    */
    function _harvest(uint256 rewardAmount) internal {
        // Update global reward accrual state and associate with the update of reward state
        _globalAccrue();

        if (rewardAmount != 0) {
            rewardState += rewardAmount;

            emit Harvest(rewardAmount);
        }
    }

    /**
        @notice Claim available pxGMX rewards
        @param  receiver  address  Receiver address
    */
    function claim(address receiver) external {
        if (receiver == address(0)) revert ZeroAddress();

        IAutoPxGlp(address(this)).compound(1, 1, true);
        _userAccrue(msg.sender);

        uint256 globalRewards = globalState.rewards;
        uint256 userRewards = userRewardStates[msg.sender].rewards;

        // Claim should be skipped and not reverted on zero global/user reward
        if (globalRewards != 0 && userRewards != 0) {
            // Update global and user reward states to reflect the claim
            globalState.rewards = globalRewards - userRewards;
            userRewardStates[msg.sender].rewards = 0;

            // Transfer the proportionate reward token amounts to the recipient
            uint256 _rewardState = rewardState;
            uint256 amount = (_rewardState * userRewards) / globalRewards;

            if (amount != 0) {
                // Update reward state (i.e. amount) to reflect reward tokens transferred out
                rewardState = _rewardState - amount;

                pxGmx.safeTransfer(receiver, amount);

                emit PxGmxClaimed(msg.sender, receiver, amount);
            }
        }
    }
}
