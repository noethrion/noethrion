// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

contract NoethrionTokenTest is Test {
    NoethrionToken internal token;

    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new NoethrionToken(admin);
        vm.prank(admin);
        token.authorizeMinter(minter);
    }

    // ───── Metadata ─────

    function test_Metadata() public view {
        assertEq(token.name(), "Noethrion");
        assertEq(token.symbol(), "NOET");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
    }

    // ───── Minting ─────

    function test_Mint_Succeeds() public {
        vm.prank(minter);
        token.mint(alice, 1_000 ether);
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.totalSupply(), 1_000 ether);
    }

    function test_Mint_RevertsForNonMinter() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1 ether);
    }

    function test_Mint_RevertsOnZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(NoethrionToken.ZeroAddress.selector);
        token.mint(address(0), 1 ether);
    }

    function test_Mint_RevertsOnZeroAmount() public {
        vm.prank(minter);
        vm.expectRevert(NoethrionToken.ZeroAmount.selector);
        token.mint(alice, 0);
    }

    function test_Mint_RevertsOverCap() public {
        uint256 cap = token.MAX_SUPPLY();
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(NoethrionToken.MaxSupplyExceeded.selector, cap + 1, cap)
        );
        token.mint(alice, cap + 1);
    }

    // ───── Role admin ─────

    function test_AuthorizeMinter_OnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        token.authorizeMinter(bob);
    }

    function test_RevokeMinter() public {
        vm.prank(admin);
        token.revokeMinter(minter);
        vm.prank(minter);
        vm.expectRevert();
        token.mint(alice, 1 ether);
    }

    // ───── Construction ─────

    function test_Constructor_RevertsOnZeroAdmin() public {
        vm.expectRevert(NoethrionToken.ZeroAddress.selector);
        new NoethrionToken(address(0));
    }

    function test_AuthorizeMinter_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(NoethrionToken.ZeroAddress.selector);
        token.authorizeMinter(address(0));
    }

    // ───── Remaining mintable ─────

    function test_RemainingMintable_InitiallyMax() public view {
        assertEq(token.remainingMintable(), token.MAX_SUPPLY());
    }

    function test_RemainingMintable_DecreasesOnMint() public {
        uint256 mintAmount = 1_000 ether;
        vm.prank(minter);
        token.mint(alice, mintAmount);
        assertEq(token.remainingMintable(), token.MAX_SUPPLY() - mintAmount);
    }

    function test_RemainingMintable_ZeroAtCap() public {
        uint256 cap = token.MAX_SUPPLY();
        vm.prank(minter);
        token.mint(alice, cap);
        assertEq(token.remainingMintable(), 0);
    }

    // ───── Fuzz ─────

    function testFuzz_Mint(uint128 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= token.MAX_SUPPLY());
        vm.prank(minter);
        token.mint(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }
}
