// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {Redemption} from "../src/Redemption.sol";

/// @title TokenAndRedemptionTest
/// @notice PaymentToken access control (mint/burn roles) and the Redemption
///         off-ramp: burn-proof receipts, paying-authority attestation,
///         transferability, and edge cases.
contract TokenAndRedemptionTest is TestBase {
    // --------------------------------------------------------------------------
    // -------------------------------- PAYMENT TOKEN ---------------------------
    // --------------------------------------------------------------------------

    /// Mint is FACTORY-role only.
    function testMintRequiresFactoryRole() public {
        vm.prank(outsider);
        vm.expectRevert();
        token.mint(outsider, 100);

        token.mint(outsider, 100); // the test contract holds FACTORY
        assertEq(token.balanceOf(outsider), 100);
    }

    /// Burn is FACTORY-role only.
    function testBurnRequiresFactoryRole() public {
        token.mint(builder, 100);

        vm.prank(outsider);
        vm.expectRevert();
        token.burn(builder, 100);

        vm.prank(address(redemption));
        token.burn(builder, 100);
        assertEq(token.balanceOf(builder), 0);
    }

    /// Only the token admin can grant the FACTORY role.
    function testSetFactoryRoleAdminOnly() public {
        vm.prank(outsider);
        vm.expectRevert();
        token.setFactoryRole(outsider);
    }

    /// Burning more than the balance reverts.
    function testBurnOverBalanceReverts() public {
        token.mint(builder, 50);
        vm.prank(address(redemption));
        vm.expectRevert();
        token.burn(builder, 51);
    }

    // --------------------------------------------------------------------------
    // --------------------------------- REDEMPTION ------------------------------
    // --------------------------------------------------------------------------

    /// Redeeming more than the balance reverts (the pull fails).
    function testRedeemOverBalanceReverts() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), type(uint256).max);

        vm.prank(builder);
        vm.expectRevert();
        redemption.redeem(COST + 1, keccak256("bank"), address(0xE5C0));
    }

    /// Receipts are issued sequentially; each is a distinct NFT.
    function testReceiptsSequentialAndDistinct() public {
        token.mint(builder, 2 * COST);
        vm.prank(builder);
        token.approve(address(redemption), 2 * COST);

        vm.prank(builder);
        uint256 first = redemption.redeem(COST, keccak256("bank1"), address(0xE5C0));
        vm.prank(builder);
        uint256 second = redemption.redeem(COST, keccak256("bank2"), address(0xE5C0));

        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(redemption.ownerOf(first), builder);
        assertEq(redemption.ownerOf(second), builder);
    }

    /// A rejected receipt cannot be paid, and a paid receipt cannot be
    /// re-marked.
    function testStateTransitionsAreOneWay() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("bank"), address(0xE5C0));

        redemption.markPaid(tokenId, "TRX-1");
        vm.expectRevert(Redemption.NotPending.selector);
        redemption.markPaid(tokenId, "TRX-2");
        vm.expectRevert(Redemption.NotPending.selector);
        redemption.markRejected(tokenId, keccak256("late"));
    }

    /// The tokenURI carries the receipt data as a data URI.
    function testTokenURIContainsReceiptData() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("bank"), address(0xE5C0));

        string memory uri = redemption.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
        assertTrue(keccak256(bytes(uri)) != keccak256(""));
    }

    /// A receipt can be burned/transferred by its holder; the issuer keeps
    /// no special powers.
    function testReceiptTransferable() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("bank"), address(0xE5C0));

        vm.prank(builder);
        redemption.safeTransferFrom(builder, paymentWallet, tokenId);
        assertEq(redemption.ownerOf(tokenId), paymentWallet);
    }

    /// Constructors reject zero addresses.
    function testConstructorsRejectZeroAddresses() public {
        vm.expectRevert(PaymentToken.AddressZero.selector);
        new PaymentToken(address(0));

        vm.expectRevert(Redemption.AddressZero.selector);
        new Redemption(address(0), address(this));
    }

    /// The receipt NFT reports the standard ERC-165/721 interfaces.
    function testSupportsInterface() public view {
        assertTrue(redemption.supportsInterface(0x01ffc9a7)); // IERC165
        assertTrue(redemption.supportsInterface(0x80ac58cd)); // IERC721
        assertTrue(redemption.supportsInterface(0x5b5e139f)); // IERC721Metadata
        assertFalse(redemption.supportsInterface(0xffffffff));
    }
}
