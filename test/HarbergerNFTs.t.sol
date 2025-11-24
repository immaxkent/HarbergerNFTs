// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {HarbergerNFTs} from "../src/HarbergerNFTs.sol";

contract HarbergerNFTsTest is Test {
    HarbergerNFTs public nft;

    address public treasurer = address(0xea);
    address public owner = address(0xe);
    address public buyer = address(0xbe);
    address public nonOwner = address(0x1e);

    uint256 public constant MAX_PRICE = 1e18;
    uint256 public constant MIN_PRICE = 0.001 ether;
    uint256 public constant TAX_RATE = 1000; // 10% annual, arbitrarily asigned
    uint256 public constant CLIFF = 2628002; // initialisaed at == minimum (1 month)

    uint256 public constant TOKEN_ID = 1;
    uint256 public constant INITIAL_PRICE = 1 ether;

    event NFTMinted(uint256 indexed tokenId, address indexed owner, uint256 price);
    event NFTModified(uint256 indexed tokenId, address indexed owner, uint256 newPrice);
    event NFTPurchased(uint256 indexed tokenId, address indexed from, address indexed to, uint256 price);
    event NFTDefaulted(uint256 indexed tokenId, address indexed previousOwner);
    event TaxPaid(uint256 indexed tokenId, address indexed payer, uint256 amount);

    function setUp() public {
        nft = new HarbergerNFTs(treasurer, MAX_PRICE, MIN_PRICE, TAX_RATE, CLIFF, "Harberger NFT", "HARB");
        vm.deal(owner, 100 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(nonOwner, 100 ether);
        vm.deal(treasurer, 100 ether);
    }

    ////////////////////////////// mint()

    function test_Mint() public {
        vm.expectEmit(true, true, false, true);
        emit NFTMinted(TOKEN_ID, owner, INITIAL_PRICE);
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        assertEq(nft.ownerOf(TOKEN_ID), owner);
        assertEq(nft.getPrice(TOKEN_ID), INITIAL_PRICE);
        assertEq(nft.balanceOf(owner), 1);
    }

    // mint revert paths

    function test_Mint_CheckZeroAddresReverts() public {
        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.ZeroAddress.selector);
        nft.mint(address(0), TOKEN_ID, INITIAL_PRICE);
    }

    function test_Mint_CheckMinPOrice() public {
        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.InvalidPrice.selector);
        nft.mint(owner, TOKEN_ID, MIN_PRICE - 1);
    }

    function test_Mint_CheckMaxPrice() public {
        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.InvalidPrice.selector);
        nft.mint(owner, TOKEN_ID, MAX_PRICE + 1);
    }

    function test_Mint_CheckZeroPrice() public {
        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.InvalidPrice.selector);
        nft.mint(owner, TOKEN_ID, 0);
    }

    function test_Mint_RevertsIfTokenIdAlreadyExists() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.InvalidToken.selector);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
    }

    function test_Mint_MultipleTokens() public {
        vm.prank(owner);
        nft.mint(owner, 1, INITIAL_PRICE);

        uint256 price2 = 0.5 ether;

        vm.prank(owner);
        nft.mint(owner, 2, price2);
        assertEq(nft.balanceOf(owner), 2);
        assertEq(nft.getPrice(1), INITIAL_PRICE);
        assertEq(nft.getPrice(2), price2);
    }

    ////////////////////////////// modify()

    function test_Modify() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);

        uint256 newPrice = 0.5 ether;
        vm.expectEmit(true, true, false, true);
        emit NFTModified(TOKEN_ID, owner, newPrice);
        vm.prank(owner);
        nft.modify{value: taxDue}(TOKEN_ID, newPrice);

        assertEq(nft.getPrice(TOKEN_ID), newPrice);
    }

    function test_Modify_CheckNonOwnerModifyCall() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 30);

        vm.prank(nonOwner);
        vm.expectRevert(HarbergerNFTs.NotOwner.selector);
        nft.modify{value: 0}(TOKEN_ID, 0.5 ether);
    }

    function test_Modify_CheckBlockTimeMarginNotMet() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.BlockTimeMarginNotMet.selector);
        nft.modify{value: 0}(TOKEN_ID, 2 ether);
    }

    function test_Modify_PayTaxBeforeUpdating() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        // advance time to accrue tax
        vm.warp(block.timestamp + 3 days);

        vm.warp(block.timestamp + 30); // give some time for block.timestamp to update
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        assertGt(taxDue, 0);

        uint256 treasuryBalanceBefore = address(treasurer).balance;
        uint256 newPrice = 0.5 ether;
        vm.prank(owner);
        nft.modify{value: taxDue}(TOKEN_ID, newPrice);

        assertEq(address(treasurer).balance, treasuryBalanceBefore + taxDue);
    }

    ////////////////////////////// purchase()

    function test_Purchase() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 totalRequired = INITIAL_PRICE + taxDue;

        uint256 buyerBalanceBefore = buyer.balance;
        uint256 ownerBalanceBefore = owner.balance;

        vm.expectEmit(true, true, true, true);
        emit NFTPurchased(TOKEN_ID, owner, buyer, INITIAL_PRICE);

        vm.prank(buyer);
        nft.purchase{value: totalRequired}(TOKEN_ID);

        assertEq(nft.ownerOf(TOKEN_ID), buyer);
        assertEq(buyer.balance, buyerBalanceBefore - totalRequired);
        assertEq(owner.balance, ownerBalanceBefore + INITIAL_PRICE);
    }

    function test_Modify_CheckBlockTimeMargin() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.prank(buyer);
        vm.expectRevert(HarbergerNFTs.BlockTimeMarginNotMet.selector);
        nft.purchase{value: INITIAL_PRICE}(TOKEN_ID);
    }

    function test_Purchase_CheckPaymentVolume() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 30);

        vm.prank(buyer);
        vm.expectRevert(HarbergerNFTs.InsufficientPayment.selector);
        nft.purchase{value: INITIAL_PRICE - 1}(TOKEN_ID);
    }

    function test_Purchase_RefundsExcess() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 totalRequired = INITIAL_PRICE + taxDue;

        uint256 totalPayment = totalRequired + 0.5 ether;
        uint256 buyerBalanceBefore = buyer.balance;
        vm.prank(buyer);
        nft.purchase{value: totalPayment}(TOKEN_ID);

        assertEq(buyer.balance, buyerBalanceBefore - totalRequired);
    }

    function test_Purchase_PayTreasury() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        //accrue tax
        vm.warp(block.timestamp + 3 days);

        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 totalRequired = INITIAL_PRICE + taxDue;
        uint256 treasuryBalanceBefore = address(treasurer).balance;

        vm.prank(buyer);
        nft.purchase{value: totalRequired}(TOKEN_ID);

        assertEq(address(treasurer).balance, treasuryBalanceBefore + taxDue);
    }

    function test_Purchase_TimestampUpdate() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        uint64 initialTimestamp = nft.getTimestamp(TOKEN_ID);

        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 totalRequired = INITIAL_PRICE + taxDue;
        vm.prank(buyer);
        nft.purchase{value: totalRequired}(TOKEN_ID);

        uint64 newTimestamp = nft.getTimestamp(TOKEN_ID);
        assertGt(newTimestamp, initialTimestamp);
    }

    function test_Purchase_WorksPastCliff() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        // Advance past cliff
        vm.warp(block.timestamp + 30); // Block time margin
        vm.warp(block.timestamp + CLIFF);

        // purchase should work past cliff - can still buy and pay tax
        // (defaulting is explicit via evaluateAndAddress)
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        assertGt(taxDue, 0); // Tax has accrued past cliff
        uint256 totalRequired = INITIAL_PRICE + taxDue;

        uint256 buyerBalanceBefore = buyer.balance;
        uint256 ownerBalanceBefore = owner.balance;
        uint256 treasuryBalanceBefore = address(treasurer).balance;

        vm.prank(buyer);
        nft.purchase{value: totalRequired}(TOKEN_ID);

        assertEq(nft.ownerOf(TOKEN_ID), buyer);
        assertEq(buyer.balance, buyerBalanceBefore - totalRequired);
        assertEq(owner.balance, ownerBalanceBefore + INITIAL_PRICE);
        assertEq(address(treasurer).balance, treasuryBalanceBefore + taxDue);
        assertEq(nft.returnTaxDue(TOKEN_ID), 0);
        assertFalse(nft.isDefaulted(TOKEN_ID));
    }

    ////////////////////////////// returnTaxDue()

    function test_TaxAccrual() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        vm.warp(block.timestamp + 1 days);

        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        assertGt(taxDue, 0);

        vm.warp(block.timestamp + 1 days);
        uint256 taxDueAfter2Days = nft.returnTaxDue(TOKEN_ID);
        assertGt(taxDueAfter2Days, taxDue);
    }

    function test_TaxFormula() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        vm.warp(block.timestamp + 365 days);

        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);

        //should be 10% of price after 1 year
        // (price * taxRate * timeElapsed) / (365 days * 10_000) == (1 ether * 1000 * 365 days) / (365 days * 10_000) ~= 0.1 ether
        uint256 expectedTax = (INITIAL_PRICE * TAX_RATE) / 10_000;
        assertEq(taxDue, expectedTax);
    }

    function test_TaxResetsAfterPayment() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        vm.warp(block.timestamp + 1 days);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);

        vm.prank(owner);
        nft.payTax{value: taxDue}(TOKEN_ID);
        uint256 taxAfterPayment = nft.returnTaxDue(TOKEN_ID);
        assertEq(taxAfterPayment, 0);
    }

    function test_TaxResetsAfterModify() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 1 days);

        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 newPrice = 0.5 ether;
        vm.prank(owner);
        nft.modify{value: taxDue}(TOKEN_ID, newPrice);

        uint256 taxAfterModify = nft.returnTaxDue(TOKEN_ID);
        assertEq(taxAfterModify, 0);
    }

    function test_TaxResetAfterPurchase() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 1 days);
        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 totalRequired = INITIAL_PRICE + taxDue;

        vm.prank(buyer);
        nft.purchase{value: totalRequired}(TOKEN_ID);

        uint256 taxAfterPurchase = nft.returnTaxDue(TOKEN_ID);
        assertEq(taxAfterPurchase, 0);
    }

    ////////////////////////////// payTax()

    function test_PayTax() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 1 days);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);

        uint256 treasuryBalanceBefore = address(treasurer).balance;

        vm.expectEmit(true, true, false, true);
        emit TaxPaid(TOKEN_ID, owner, taxDue);
        vm.prank(owner);
        nft.payTax{value: taxDue}(TOKEN_ID);

        assertEq(address(treasurer).balance, treasuryBalanceBefore + taxDue);
        assertEq(nft.returnTaxDue(TOKEN_ID), 0);
    }

    function test_PayTax_RevertIfInsufficient() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 1 days);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);

        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.InsufficientPayment.selector);
        nft.payTax{value: taxDue - 1}(TOKEN_ID);
    }

    ////////////////////////////// evaluateAndAddress()

    function test_Default_OccursAfterCliff() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        //advance past cliff + margin
        vm.warp(block.timestamp + CLIFF + 30);
        vm.expectEmit(true, true, false, true);
        emit NFTDefaulted(TOKEN_ID, owner);

        vm.prank(owner);
        nft.evaluateAndAddress(TOKEN_ID);
        assertTrue(nft.isDefaulted(TOKEN_ID));
        assertEq(nft.ownerOf(TOKEN_ID), treasurer);
    }

    function test_Default_DoesNotOccurBeforeCliff() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);
        vm.warp(block.timestamp + CLIFF - 5);

        vm.prank(owner);
        nft.evaluateAndAddress(TOKEN_ID);
        assertFalse(nft.isDefaulted(TOKEN_ID));
        assertEq(nft.ownerOf(TOKEN_ID), owner);
    }

    ////////////////////////////// edge cases

    function test_VeryLongTimeInterval() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        // + 10 years
        vm.warp(block.timestamp + 10 * 365 days);

        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);

        // == 10% * 10 years = 100%
        uint256 expectedTax = INITIAL_PRICE;
        assertEq(taxDue, expectedTax);
    }

    function test_MaxTax() public {
        HarbergerNFTs nftMaxTax = new HarbergerNFTs(
            treasurer,
            MAX_PRICE,
            MIN_PRICE,
            10_000, // 100%
            CLIFF,
            "Harberger NFT",
            "HARB"
        );

        vm.prank(owner);
        nftMaxTax.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 365 days);

        uint256 taxDue = nftMaxTax.returnTaxDue(TOKEN_ID);
        assertEq(taxDue, INITIAL_PRICE);
    }

    /////////////////////////////////////////////////////////////////
    function test_RoundingSmallAmounts() public {
        // @audit found that we weren't sensing small changes here post scaling implementation
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, MIN_PRICE);

        // advance 1 hour
        vm.warp(block.timestamp + 1 hours);

        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        // with scaling factor, tax should be non-zero
        assertGt(taxDue, 0);
        assertGe(taxDue, 1e7); // >0.00000001 ether
    }
    /////////////////////////////////////////////////////////////////

    function test_RevertIfPurchaseThenImmediatelyModify() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + 30);
        uint256 taxDue = nft.returnTaxDue(TOKEN_ID);
        uint256 totalRequired = INITIAL_PRICE + taxDue;
        vm.prank(buyer);
        nft.purchase{value: totalRequired}(TOKEN_ID);
        vm.prank(buyer);
        vm.expectRevert(HarbergerNFTs.BlockTimeMarginNotMet.selector);
        nft.modify{value: 0}(TOKEN_ID, 0.5 ether);
    }

    function test_DefaultedNFTCannotBePurchasedBack() public {
        vm.prank(owner);
        nft.mint(owner, TOKEN_ID, INITIAL_PRICE);

        vm.warp(block.timestamp + CLIFF + 30);
        vm.prank(owner);
        nft.evaluateAndAddress(TOKEN_ID);
        vm.warp(block.timestamp + 30);
        vm.prank(owner);
        vm.expectRevert(HarbergerNFTs.TokenDefaulted.selector);
        nft.purchase{value: INITIAL_PRICE}(TOKEN_ID);
    }
}
