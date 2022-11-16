// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {PxERC20} from "src/PxERC20.sol";
import {Helper} from "./Helper.sol";

contract PxGlpTest is Helper {
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

        vm.expectRevert(_encodeRoleError(invalidCaller, pxGlp.MINTER_ROLE()));
        vm.prank(invalidCaller);

        pxGlp.mint(to, amount);
    }

    /**
        @notice Test tx success: mint pxGLP
        @param  amount  uint224  Amount to mint
     */
    function testMint(uint224 amount) external {
        vm.assume(amount != 0);

        address to = address(this);
        uint256 expectedPreMintBalance = 0;

        assertEq(expectedPreMintBalance, pxGlp.balanceOf(to));

        vm.prank(address(pirexGmx));
        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Transfer(address(0), to, amount);

        pxGlp.mint(to, amount);

        uint256 expectedPostMintBalance = expectedPreMintBalance + amount;

        assertEq(expectedPostMintBalance, pxGlp.balanceOf(to));
    }

    /*//////////////////////////////////////////////////////////////
                        burn TESTS
    //////////////////////////////////////////////////////////////*/

    /**
        @notice Test tx reversion: caller does not have the burner role
     */
    function testCannotBurnNoBurnerRole() external {
        address invalidCaller = testAccounts[0];
        address from = address(this);
        uint256 amount = 1;

        vm.expectRevert(_encodeRoleError(invalidCaller, pxGlp.BURNER_ROLE()));
        vm.prank(invalidCaller);

        pxGlp.burn(from, amount);
    }

    /**
        @notice Test tx success: burn pxGLP
        @param  amount  uint224  Amount to burn
     */
    function testBurn(uint224 amount) external {
        vm.assume(amount != 0);

        address from = address(this);

        vm.startPrank(address(pirexGmx));

        // Mint tokens which will be burned
        pxGlp.mint(from, amount);

        uint256 expectedPreBurnBalance = amount;

        assertEq(expectedPreBurnBalance, pxGlp.balanceOf(from));

        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Transfer(from, address(0), amount);

        pxGlp.burn(from, amount);

        vm.stopPrank();

        uint256 expectedPostBurnBalance = expectedPreBurnBalance - amount;

        assertEq(expectedPostBurnBalance, pxGlp.balanceOf(from));
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
        pxGlp.mint(from, mintAmount);

        assertLt(pxGlp.balanceOf(from), transferAmount);

        vm.expectRevert(stdError.arithmeticError);

        pxGlp.transfer(to, transferAmount);
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
        pxGlp.mint(from, mintAmount);

        uint256 expectedPreTransferBalanceFrom = mintAmount;
        uint256 expectedPreTransferBalanceTo = 0;

        assertEq(expectedPreTransferBalanceFrom, pxGlp.balanceOf(from));
        assertEq(expectedPreTransferBalanceTo, pxGlp.balanceOf(to));
        assertGt(expectedPreTransferBalanceFrom, transferAmount);

        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Transfer(from, to, transferAmount);

        pxGlp.transfer(to, transferAmount);

        uint256 expectedPostTransferBalanceFrom = expectedPreTransferBalanceFrom -
                transferAmount;
        uint256 expectedPostTransferBalanceTo = expectedPreTransferBalanceTo +
            transferAmount;

        assertEq(expectedPostTransferBalanceFrom, pxGlp.balanceOf(from));
        assertEq(expectedPostTransferBalanceTo, pxGlp.balanceOf(to));
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
        pxGlp.mint(from, mintAmount);

        vm.prank(from);

        pxGlp.approve(caller, allowanceAmount);

        assertGt(transferAmount, pxGlp.balanceOf(from));
        assertLe(transferAmount, pxGlp.allowance(from, caller));

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller);

        pxGlp.transferFrom(from, to, transferAmount);
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
        pxGlp.mint(from, mintAmount);

        vm.prank(from);

        pxGlp.approve(caller, allowanceAmount);

        assertLe(transferAmount, pxGlp.balanceOf(from));
        assertGt(transferAmount, pxGlp.allowance(from, caller));

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(caller);

        pxGlp.transferFrom(from, to, transferAmount);
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
        pxGlp.mint(from, mintAmount);

        vm.prank(from);
        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Approval(from, caller, allowanceAmount);

        pxGlp.approve(caller, allowanceAmount);

        uint256 expectedPreTransferBalanceFrom = mintAmount;
        uint256 expectedPreTransferBalanceTo = 0;
        uint256 expectedPreTransferAllowanceCaller = allowanceAmount;

        assertEq(expectedPreTransferBalanceFrom, pxGlp.balanceOf(from));
        assertEq(expectedPreTransferBalanceTo, pxGlp.balanceOf(to));
        assertEq(
            expectedPreTransferAllowanceCaller,
            pxGlp.allowance(from, caller)
        );

        vm.expectEmit(true, true, false, true, address(pxGlp));

        emit Transfer(from, to, transferAmount);

        vm.prank(caller);

        pxGlp.transferFrom(from, to, transferAmount);

        uint256 expectedPostTransferBalanceFrom = expectedPreTransferBalanceFrom -
                transferAmount;
        uint256 expectedPostTransferBalanceTo = expectedPreTransferBalanceTo +
            transferAmount;
        uint256 expectedPostTransferAllowanceCaller = expectedPreTransferAllowanceCaller -
                transferAmount;

        assertEq(expectedPostTransferBalanceFrom, pxGlp.balanceOf(from));
        assertEq(expectedPostTransferBalanceTo, pxGlp.balanceOf(to));
        assertEq(
            expectedPostTransferAllowanceCaller,
            pxGlp.allowance(from, caller)
        );
    }
}
