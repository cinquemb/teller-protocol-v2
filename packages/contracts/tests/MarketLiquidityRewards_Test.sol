// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/TellerV2MarketForwarder.sol";

import "./resolvers/TestERC20Token.sol";
import "../contracts/TellerV2Context.sol";

import { Testable } from "./Testable.sol";

import { Collateral, CollateralType } from "../contracts/interfaces/escrow/ICollateralEscrowV1.sol";

import { User } from "./Test_Helpers.sol";

import "../contracts/mock/MarketRegistryMock.sol";
import "../contracts/mock/CollateralManagerMock.sol";

import "../contracts/MarketLiquidityRewards.sol";

contract MarketLiquidityRewards_Test is Testable, MarketLiquidityRewards {
    MarketLiquidityUser private marketOwner;
    MarketLiquidityUser private lender;
    MarketLiquidityUser private borrower;

    uint256 immutable startTime = 1678122531;

    //  address tokenAddress;
    uint256 marketId;
    uint256 maxAmount;

    address[] emptyArray;
    address[] borrowersArray;

    uint32 maxLoanDuration;
    uint16 minInterestRate;
    uint32 expiration;

    TestERC20Token rewardToken;
    uint8 constant rewardTokenDecimals = 18;

    TestERC20Token principalToken;
    uint8 constant principalTokenDecimals = 18;

    TestERC20Token collateralToken;
    uint8 constant collateralTokenDecimals = 6;

    bool verifyLoanStartTimeWasCalled;
    bool verifyPrincipalTokenAddressWasCalled;
    bool verifyCollateralTokenAddressWasCalled;

    bool verifyRewardRecipientWasCalled;
    bool verifyCollateralAmountWasCalled;

    constructor()
        MarketLiquidityRewards(
            address(new TellerV2Mock()),
            address(new MarketRegistryMock(address(0))),
            address(new CollateralManagerMock())
        )
    {}

    function setUp() public {
        marketOwner = new MarketLiquidityUser(address(tellerV2), (this));
        borrower = new MarketLiquidityUser(address(tellerV2), (this));
        lender = new MarketLiquidityUser(address(tellerV2), (this));
        TellerV2Mock(tellerV2).__setMarketOwner(marketOwner);

        MarketRegistryMock(marketRegistry).setMarketOwner(address(marketOwner));

        //tokenAddress = address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        marketId = 2;
        maxAmount = 100000000000000000000;
        maxLoanDuration = 2480000;
        minInterestRate = 3000;
        expiration = uint32(block.timestamp) + uint32(64000);

        marketOwner.setTrustedMarketForwarder(marketId, address(this));
        lender.approveMarketForwarder(marketId, address(this));

        borrowersArray = new address[](1);
        borrowersArray[0] = address(borrower);

        rewardToken = new TestERC20Token(
            "Test Wrapped ETH",
            "TWETH",
            100000,
            rewardTokenDecimals
        );

        principalToken = new TestERC20Token(
            "Test Wrapped ETH",
            "TWETH",
            100000,
            principalTokenDecimals
        );

        collateralToken = new TestERC20Token(
            "Test USDC",
            "TUSDC",
            100000,
            collateralTokenDecimals
        );

        IERC20Upgradeable(address(rewardToken)).transfer(
            address(lender),
            10000
        );

        vm.warp(startTime + 100);
        //delete allocationCount;

        verifyLoanStartTimeWasCalled = false;
        verifyPrincipalTokenAddressWasCalled = false;
        verifyCollateralTokenAddressWasCalled = false;

        verifyRewardRecipientWasCalled = false;
        verifyCollateralAmountWasCalled = false;
    }

    function _setAllocation(uint256 allocationId) internal {
        uint256 rewardTokenAmount = 0;

        RewardAllocation memory _allocation = IMarketLiquidityRewards
            .RewardAllocation({
                allocator: address(lender),
                marketId: marketId,
                rewardTokenAddress: address(rewardToken),
                rewardTokenAmount: rewardTokenAmount,
                requiredPrincipalTokenAddress: address(principalToken),
                requiredCollateralTokenAddress: address(collateralToken),
                minimumCollateralPerPrincipalAmount: 0,
                rewardPerLoanPrincipalAmount: 0,
                bidStartTimeMin: uint32(startTime),
                bidStartTimeMax: uint32(startTime + 10000),
                allocationStrategy: AllocationStrategy.BORROWER
            });

        allocatedRewards[allocationId] = _allocation;
    }

    function test_allocateRewards() public {
        uint256 rewardTokenAmount = 500;

        RewardAllocation memory _allocation = IMarketLiquidityRewards
            .RewardAllocation({
                allocator: address(lender),
                marketId: marketId,
                rewardTokenAddress: address(rewardToken),
                rewardTokenAmount: rewardTokenAmount,
                requiredPrincipalTokenAddress: address(principalToken),
                requiredCollateralTokenAddress: address(collateralToken),
                minimumCollateralPerPrincipalAmount: 0,
                rewardPerLoanPrincipalAmount: 0,
                bidStartTimeMin: uint32(startTime),
                bidStartTimeMax: uint32(startTime + 10000),
                allocationStrategy: AllocationStrategy.BORROWER
            });

        lender._approveERC20Token(
            address(rewardToken),
            address(this),
            rewardTokenAmount
        );

        uint256 allocationId = lender._allocateRewards(_allocation);

        /*  assertEq(
            allocationId,
            address(lender),
            "Allocate r"
        );*/
    }

    function test_increaseAllocationAmount() public {
        uint256 allocationId = 0;
        uint256 amountToIncrease = 100;

        _setAllocation(allocationId);

        uint256 amountBefore = allocatedRewards[allocationId].rewardTokenAmount;

        lender._approveERC20Token(
            address(rewardToken),
            address(this),
            amountToIncrease
        );

        lender._increaseAllocationAmount(allocationId, amountToIncrease);

        uint256 amountAfter = allocatedRewards[allocationId].rewardTokenAmount;

        assertEq(
            amountAfter,
            amountBefore + amountToIncrease,
            "Allocation did not increase"
        );
    }

    /*

    deallocate

*/

    function test_deallocateRewards() public {
        uint256 allocationId = 0;

        _setAllocation(allocationId);

        uint256 amountBefore = allocatedRewards[allocationId].rewardTokenAmount;

        lender._deallocateRewards(allocationId, amountBefore);

        uint256 amountAfter = allocatedRewards[allocationId].rewardTokenAmount;

        assertEq(amountAfter, 0, "Allocation was not deleted");
    }

    /*
    claim rewards 
*/

    function test_claimRewards() public {
        Bid memory mockBid;

        mockBid.borrower = address(borrower);
        mockBid.lender = address(lender);
        mockBid.marketplaceId = marketId;
        mockBid.loanDetails.lendingToken = (principalToken);
        mockBid.loanDetails.principal = 0;
        mockBid.loanDetails.acceptedTimestamp = uint32(block.timestamp);
        mockBid.state = BidState.PAID;

        TellerV2Mock(tellerV2).setMockBid(mockBid);

        uint256 allocationId = 0;
        uint256 bidId = 0;

        _setAllocation(allocationId);

        borrower._claimRewards(allocationId, bidId);

        assertEq(
            verifyLoanStartTimeWasCalled,
            true,
            "verifyLoanStartTime was not called"
        );

        assertEq(
            verifyPrincipalTokenAddressWasCalled,
            true,
            " verifyPrincipalTokenAddress was not called"
        );

        assertEq(
            verifyCollateralTokenAddressWasCalled,
            true,
            "verifyCollateralTokenAddress was not called"
        );

        assertEq(
            verifyRewardRecipientWasCalled,
            true,
            "verifyRewardRecipient was not called"
        );

        assertEq(
            verifyCollateralAmountWasCalled,
            true,
            "verifyCollateralAmount was not called"
        );

        //add some negative tests  (unit)
        //add comments to all of the methods
    }

    function test_calculateRewardAmount_weth_principal() public {
        uint256 loanPrincipal = 1e8;
        uint256 principalTokenDecimals = 18;

        uint256 rewardPerLoanPrincipalAmount = 1e16; // expanded by token decimals so really 0.01

        uint256 rewardAmount = super._calculateRewardAmount(
            loanPrincipal,
            principalTokenDecimals,
            rewardPerLoanPrincipalAmount
        );

        assertEq(rewardAmount, 1e6, "Invalid reward amount");
    }

    function test_calculateRewardAmount_usdc_principal() public {
        uint256 loanPrincipal = 1e8;
        uint256 principalTokenDecimals = 6;

        uint256 rewardPerLoanPrincipalAmount = 1e4; // expanded by token decimals so really 0.01

        uint256 rewardAmount = super._calculateRewardAmount(
            loanPrincipal,
            principalTokenDecimals,
            rewardPerLoanPrincipalAmount
        );

        assertEq(rewardAmount, 1e6, "Invalid reward amount");
    }

    function test_requiredCollateralAmount() public {
        uint256 collateralTokenDecimals = 6;

        uint256 loanPrincipal = 1e8;
        uint256 principalTokenDecimals = 6;

        uint256 minimumCollateralPerPrincipal = 1e4 * 1e6; // expanded by token decimals so really 0.01

        uint256 minCollateral = _requiredCollateralAmount(
            loanPrincipal,
            principalTokenDecimals,
            collateralTokenDecimals,
            minimumCollateralPerPrincipal
        );

        assertEq(minCollateral, 1e6, "Invalid min collateral calculation");
    }

    function allocateRewards(
        MarketLiquidityRewards.RewardAllocation calldata _allocation
    ) public override returns (uint256 allocationId_) {
        super.allocateRewards(_allocation);
    }

    function increaseAllocationAmount(
        uint256 _allocationId,
        uint256 _tokenAmount
    ) public override {
        super.increaseAllocationAmount(_allocationId, _tokenAmount);
    }

    function deallocateRewards(uint256 _allocationId, uint256 _tokenAmount)
        public
        override
    {
        super.deallocateRewards(_allocationId, _tokenAmount);
    }

    function _verifyAndReturnRewardRecipient(
        AllocationStrategy strategy,
        BidState bidState,
        address borrower,
        address lender
    ) internal override returns (address rewardRecipient) {
        verifyRewardRecipientWasCalled = true;
        return address(borrower);
    }

    function _verifyCollateralAmount(
        address _collateralTokenAddress,
        uint256 _collateralAmount,
        address _principalTokenAddress,
        uint256 _principalAmount,
        uint256 _minimumCollateralPerPrincipalAmount
    ) internal override {
        verifyCollateralAmountWasCalled = true;
    }

    function _verifyLoanStartTime(
        uint32 loanStartTime,
        uint32 minStartTime,
        uint32 maxStartTime
    ) internal override {
        verifyLoanStartTimeWasCalled = true;
    }

    function _verifyPrincipalTokenAddress(
        address loanTokenAddress,
        address expectedTokenAddress
    ) internal override {
        verifyPrincipalTokenAddressWasCalled = true;
    }

    function _verifyCollateralTokenAddress(
        address loanTokenAddress,
        address expectedTokenAddress
    ) internal override {
        verifyCollateralTokenAddressWasCalled = true;
    }
}

contract MarketLiquidityUser is User {
    MarketLiquidityRewards public immutable liquidityRewards;

    constructor(address _tellerV2, MarketLiquidityRewards _liquidityRewards)
        User(_tellerV2)
    {
        liquidityRewards = _liquidityRewards;
    }

    function _allocateRewards(
        MarketLiquidityRewards.RewardAllocation calldata _allocation
    ) public returns (uint256) {
        return liquidityRewards.allocateRewards(_allocation);
    }

    function _increaseAllocationAmount(
        uint256 _allocationId,
        uint256 _allocationAmount
    ) public {
        liquidityRewards.increaseAllocationAmount(
            _allocationId,
            _allocationAmount
        );
    }

    function _deallocateRewards(uint256 _allocationId, uint256 _amount) public {
        liquidityRewards.deallocateRewards(_allocationId, _amount);
    }

    function _claimRewards(uint256 _allocationId, uint256 _bidId) public {
        return liquidityRewards.claimRewards(_allocationId, _bidId);
    }

    function _approveERC20Token(address tokenAddress, address guy, uint256 wad)
        public
    {
        IERC20Upgradeable(tokenAddress).approve(guy, wad);
    }
}

contract TellerV2Mock is TellerV2Context {
    Bid mockBid;

    constructor() TellerV2Context(address(0)) {}

    function __setMarketOwner(User _marketOwner) external {
        marketRegistry = IMarketRegistry(
            address(new MarketRegistryMock(address(_marketOwner)))
        );
    }

    function getSenderForMarket(uint256 _marketId)
        external
        view
        returns (address)
    {
        return _msgSenderForMarket(_marketId);
    }

    function getDataForMarket(uint256 _marketId)
        external
        view
        returns (bytes calldata)
    {
        return _msgDataForMarket(_marketId);
    }

    function setMockBid(Bid calldata bid) public {
        mockBid = bid;
    }

    function getLoanSummary(uint256 _bidId)
        external
        view
        returns (
            address borrower,
            address lender,
            uint256 marketId,
            address principalTokenAddress,
            uint256 principalAmount,
            uint32 acceptedTimestamp,
            BidState bidState
        )
    {
        Bid storage bid = mockBid;

        borrower = bid.borrower;
        lender = bid.lender;
        marketId = bid.marketplaceId;
        principalTokenAddress = address(bid.loanDetails.lendingToken);
        principalAmount = bid.loanDetails.principal;
        acceptedTimestamp = bid.loanDetails.acceptedTimestamp;
        bidState = bid.state;
    }
}
