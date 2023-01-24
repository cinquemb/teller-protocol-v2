// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Testable } from "./Testable.sol";

import { TellerV2 } from "../TellerV2.sol";
import { MarketRegistry } from "../MarketRegistry.sol";
import { ReputationManager } from "../ReputationManager.sol";

import "../interfaces/IMarketRegistry.sol";
import "../interfaces/IReputationManager.sol";

import "../EAS/TellerAS.sol";

import "../mock/WethMock.sol";
import "../interfaces/IWETH.sol";

import { User } from "./Test_Helpers.sol";

import "../escrow/CollateralEscrowV1.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../LenderCommitmentForwarder.sol";
import "./resolvers/TestERC20Token.sol";

import "@mangrovedao/hardhat-test-solidity/test.sol";
import "../CollateralManager.sol";
import { Collateral } from "../interfaces/escrow/ICollateralEscrowV1.sol";
import { PaymentType } from "../libraries/V2Calculations.sol";
import { BidState, Payment } from "../TellerV2Storage.sol";

contract TellerV2_Test is Testable {
    User private marketOwner;
    User private borrower;
    User private lender;

    TellerV2 tellerV2;

    WethMock wethMock;
    TestERC20Token daiMock;
    CollateralManager collateralManager;

    uint256 marketId1;
    uint256 collateralAmount = 10;

    function setup_beforeAll() public {
        // Deploy test tokens
        wethMock = new WethMock();
        daiMock = new TestERC20Token("Dai", "DAI", 10000000);

        // Deploy Escrow beacon
        CollateralEscrowV1 escrowImplementation = new CollateralEscrowV1();
        UpgradeableBeacon escrowBeacon = new UpgradeableBeacon(
            address(escrowImplementation)
        );

        // Deploy protocol
        tellerV2 = new TellerV2(address(0));

        // Deploy MarketRegistry & ReputationManager
        IMarketRegistry marketRegistry = IMarketRegistry(new MarketRegistry());
        IReputationManager reputationManager = IReputationManager(
            new ReputationManager()
        );
        reputationManager.initialize(address(tellerV2));

        // Deploy Collateral manager
        collateralManager = new CollateralManager();
        collateralManager.initialize(address(escrowBeacon), address(tellerV2));

        // Deploy LenderCommitmentForwarder
        LenderCommitmentForwarder lenderCommitmentForwarder = new LenderCommitmentForwarder(
                address(tellerV2),
                address(marketRegistry)
            );

        address[] memory lendingTokens = new address[](2);
        lendingTokens[0] = address(wethMock);
        lendingTokens[1] = address(daiMock);

        // Initialize protocol
        tellerV2.initialize(
            50,
            address(marketRegistry),
            address(reputationManager),
            address(lenderCommitmentForwarder),
            lendingTokens,
            address(collateralManager)
        );

        // Instantiate users & balances
        marketOwner = new User(tellerV2, wethMock);
        borrower = new User(tellerV2, wethMock);
        lender = new User(tellerV2, wethMock);

        uint256 balance = 50000;
        payable(address(borrower)).transfer(balance);
        payable(address(lender)).transfer(balance * 10);
        borrower.depositToWeth(balance);
        lender.depositToWeth(balance * 10);

        daiMock.transfer(address(lender), balance * 10);
        daiMock.transfer(address(borrower), balance);
        // Approve Teller V2 for the lender's dai
        lender.addAllowance(address(daiMock), address(tellerV2), balance * 10);

        // Create a market
        marketId1 = marketOwner.createMarket(
            address(marketRegistry),
            8000,
            7000,
            5000,
            500,
            false,
            false,
            PaymentType.EMI,
            "uri://"
        );
    }

    function submitCollateralBid() public returns (uint256 bidId_) {
        Collateral memory info;
        info._amount = collateralAmount;
        info._tokenId = 0;
        info._collateralType = CollateralType.ERC20;
        info._collateralAddress = address(wethMock);

        Collateral[] memory collateralInfo = new Collateral[](1);
        collateralInfo[0] = info;

        uint256 bal = wethMock.balanceOf(address(borrower));

        // Increase allowance
        // Approve the collateral manager for the borrower's weth
        borrower.addAllowance(
            address(wethMock),
            address(collateralManager),
            info._amount
        );

        bidId_ = borrower.submitCollateralBid(
            address(daiMock),
            marketId1,
            100,
            10000,
            500,
            "metadataUri://",
            address(borrower),
            collateralInfo
        );
    }

    function acceptBid(uint256 _bidId) public {
        // Accept bid
        lender.acceptBid(_bidId);
    }

    function collateralEscrow_test() public {
        // Submit bid as borrower
        uint256 bidId = submitCollateralBid();
        // Accept bid as lender
        acceptBid(bidId);

        // Get newly created escrow
        address escrowAddress = collateralManager._escrows(bidId);
        CollateralEscrowV1 escrow = CollateralEscrowV1(escrowAddress);

        uint256 storedBidId = escrow.getBid();

        // Test that the created escrow has the same bidId and collateral stored
        Test.eq(bidId, storedBidId, "Collateral escrow was not created");

        uint256 escrowBalance = wethMock.balanceOf(escrowAddress);

        Test.eq(collateralAmount, escrowBalance, "Collateral was not stored");

        // Repay loan
        uint256 borrowerBalanceBefore = wethMock.balanceOf(address(borrower));
        Payment memory amountOwed = tellerV2.calculateAmountOwed(bidId);
        borrower.addAllowance(
            address(daiMock),
            address(tellerV2),
            amountOwed.principal + amountOwed.interest
        );
        borrower.repayLoanFull(bidId);

        // Check escrow balance
        uint256 escrowBalanceAfter = wethMock.balanceOf(escrowAddress);
        Test.eq(
            0,
            escrowBalanceAfter,
            "Collateral was not withdrawn from escrow on repayment"
        );

        // Check borrower balance for collateral
        uint256 borrowerBalanceAfter = wethMock.balanceOf(address(borrower));
        Test.eq(
            collateralAmount,
            borrowerBalanceAfter - borrowerBalanceBefore,
            "Collateral was not sent to borrower after repayment"
        );
    }
}
