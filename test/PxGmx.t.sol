// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {PxERC20} from "src/PxERC20.sol";
import {Helper} from "./Helper.sol";

contract PxGmxTest is Helper {
    /*//////////////////////////////////////////////////////////////
                            mint TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the minter role
     */
    function testCannotMintNoMinterRole() external {
        address invalidCaller = testAccounts[0];
        address to = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(invalidCaller, pxGmx.MINTER_ROLE()));
        vm.prank(invalidCaller);

        pxGmx.mint(to, amount);
    }

    /**
        @notice Test tx success: mint pxGMX
        @param  amount  uint224  Amount to mint
     */
    function testMint(uint224 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 expectedPreMintBalance = 0;

        assertEq(expectedPreMintBalance, pxGmx.balanceOf(to));

        vm.prank(address(pirexGmx));
        vm.expectEmit(true, true, false, true, address(pxGmx));

        emit Transfer(address(0), to, amount);

        pxGmx.mint(to, amount);

        uint256 expectedPostMintBalance = expectedPreMintBalance + amount;

        assertEq(expectedPostMintBalance, pxGmx.balanceOf(to));
    }

    /*//////////////////////////////////////////////////////////////
                            transfer TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: transfer exceeds balance
        @param  mintAmount      uint224  Mint amount
        @param  transferAmount  uint224  Transfer amount
     */
    function testCannotTransferInsufficientBalance(
        uint224 mintAmount,
        uint224 transferAmount
    ) external {
        vm.assume(mintAmount != 0);
        vm.assume(mintAmount < transferAmount);

        address from = address(this);
        address to = testAccounts[0];

        vm.prank(address(pirexGmx));

        // Mint tokens which will be burned
        pxGmx.mint(from, mintAmount);

        assertLt(pxGmx.balanceOf(from), transferAmount);

        vm.expectRevert(stdError.arithmeticError);

        pxGmx.transfer(to, transferAmount);
    }

    /**
        @notice Test tx success: transfer
        @param  mintAmount      uint224  Mint amount
        @param  transferAmount  uint224  Transfer amount
     */
    function testTransfer(uint224 mintAmount, uint224 transferAmount) external {
        vm.assume(transferAmount != 0);
        vm.assume(transferAmount < mintAmount);

        address from = address(this);
        address to = testAccounts[0];

        vm.prank(address(pirexGmx));

        // Mint tokens to ensure balance is sufficient for transfer
        pxGmx.mint(from, mintAmount);

        uint256 expectedPreTransferBalanceFrom = mintAmount;
        uint256 expectedPreTransferBalanceTo = 0;

        assertEq(expectedPreTransferBalanceFrom, pxGmx.balanceOf(from));
        assertEq(expectedPreTransferBalanceTo, pxGmx.balanceOf(to));
        assertGt(expectedPreTransferBalanceFrom, transferAmount);

        vm.expectEmit(true, true, false, true, address(pxGmx));

        emit Transfer(from, to, transferAmount);

        pxGmx.transfer(to, transferAmount);

        uint256 expectedPostTransferBalanceFrom = expectedPreTransferBalanceFrom -
                transferAmount;
        uint256 expectedPostTransferBalanceTo = expectedPreTransferBalanceTo +
            transferAmount;

        assertEq(expectedPostTransferBalanceFrom, pxGmx.balanceOf(from));
        assertEq(expectedPostTransferBalanceTo, pxGmx.balanceOf(to));
    }

    /*//////////////////////////////////////////////////////////////
                            transferFrom TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: transferFrom exceeds balance
        @param  mintAmount       uint224  Mint amount
        @param  transferAmount   uint224  Transfer amount
        @param  allowanceAmount  uint224  Allowance amount
     */
    function testCannotTransferFromInsufficientBalance(
        uint224 mintAmount,
        uint224 transferAmount,
        uint224 allowanceAmount
    ) external {
        vm.assume(mintAmount != 0);
        vm.assume(mintAmount < transferAmount);
        vm.assume(transferAmount <= allowanceAmount);

        address caller = address(this);
        address from = testAccounts[0];
        address to = testAccounts[1];

        vm.prank(address(pirexGmx));

        // Mint tokens which will be burned
        pxGmx.mint(from, mintAmount);

        vm.prank(from);

        pxGmx.approve(caller, allowanceAmount);

        assertGt(transferAmount, pxGmx.balanceOf(from));
        assertLe(transferAmount, pxGmx.allowance(from, caller));

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller);

        pxGmx.transferFrom(from, to, transferAmount);
    }

    /**
        @notice Test tx reversion: transferFrom exceeds allowance
        @param  mintAmount       uint224  Mint amount
        @param  transferAmount   uint224  Transfer amount
        @param  allowanceAmount  uint224  Allowance amount
     */
    function testCannotTransferFromInsufficientAllowance(
        uint224 mintAmount,
        uint224 transferAmount,
        uint224 allowanceAmount
    ) external {
        vm.assume(transferAmount != 0);
        vm.assume(transferAmount <= mintAmount);
        vm.assume(allowanceAmount < transferAmount);

        address caller = address(this);
        address from = testAccounts[0];
        address to = testAccounts[1];

        vm.prank(address(pirexGmx));

        // Mint tokens which will be burned
        pxGmx.mint(from, mintAmount);

        vm.prank(from);

        pxGmx.approve(caller, allowanceAmount);

        assertLe(transferAmount, pxGmx.balanceOf(from));
        assertGt(transferAmount, pxGmx.allowance(from, caller));

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller);

        pxGmx.transferFrom(from, to, transferAmount);
    }

    /**
        @notice Test tx success: transferFrom
        @param  mintAmount       uint224  Mint amount
        @param  transferAmount   uint224  Transfer amount
        @param  allowanceAmount  uint224  Allowance amount
     */
    function testTransferFrom(
        uint224 mintAmount,
        uint224 transferAmount,
        uint224 allowanceAmount
    ) external {
        vm.assume(transferAmount != 0);
        vm.assume(transferAmount <= mintAmount);
        vm.assume(transferAmount <= allowanceAmount);

        address caller = address(this);
        address from = testAccounts[0];
        address to = testAccounts[1];

        vm.prank(address(pirexGmx));

        // Mint tokens which will be burned
        pxGmx.mint(from, mintAmount);

        vm.prank(from);
        vm.expectEmit(true, true, false, true, address(pxGmx));

        emit Approval(from, caller, allowanceAmount);

        pxGmx.approve(caller, allowanceAmount);

        uint256 expectedPreTransferBalanceFrom = mintAmount;
        uint256 expectedPreTransferBalanceTo = 0;
        uint256 expectedPreTransferAllowanceCaller = allowanceAmount;

        assertEq(expectedPreTransferBalanceFrom, pxGmx.balanceOf(from));
        assertEq(expectedPreTransferBalanceTo, pxGmx.balanceOf(to));
        assertEq(
            expectedPreTransferAllowanceCaller,
            pxGmx.allowance(from, caller)
        );

        vm.expectEmit(true, true, false, true, address(pxGmx));

        emit Transfer(from, to, transferAmount);

        vm.prank(caller);

        pxGmx.transferFrom(from, to, transferAmount);

        uint256 expectedPostTransferBalanceFrom = expectedPreTransferBalanceFrom -
                transferAmount;
        uint256 expectedPostTransferBalanceTo = expectedPreTransferBalanceTo +
            transferAmount;
        uint256 expectedPostTransferAllowanceCaller = expectedPreTransferAllowanceCaller -
                transferAmount;

        assertEq(expectedPostTransferBalanceFrom, pxGmx.balanceOf(from));
        assertEq(expectedPostTransferBalanceTo, pxGmx.balanceOf(to));
        assertEq(
            expectedPostTransferAllowanceCaller,
            pxGmx.allowance(from, caller)
        );
    }
}
