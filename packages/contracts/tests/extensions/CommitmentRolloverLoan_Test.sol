import { Testable } from "../Testable.sol";

import { CommitmentRolloverLoan } from "../../contracts/LenderCommitmentForwarder/extensions/CommitmentRolloverLoan.sol";


import "../../contracts/interfaces/ICommitmentRolloverLoan.sol";
import "../../contracts/interfaces/ILenderCommitmentForwarder.sol";


import {WethMock} from "../../contracts/mock/WethMock.sol";

import {TellerV2SolMock} from "../../contracts/mock/TellerV2SolMock.sol";
import {LenderCommitmentForwarderMock} from "../../contracts/mock/LenderCommitmentForwarderMock.sol";
 
contract CommitmentRolloverLoanMock is CommitmentRolloverLoan {
    
     constructor(address _tellerV2, address _lenderCommitmentForwarder) 
     CommitmentRolloverLoan(_tellerV2, _lenderCommitmentForwarder) {
        
    }

    function acceptCommitment(AcceptCommitmentArgs calldata _commitmentArgs) public returns (uint256 bidId_){
        bidId_ = super._acceptCommitment(_commitmentArgs);
    }


}

contract CommitmentRolloverLoan_Test is Testable {
    constructor() {}

    User private borrower;
    User private lender;

    CommitmentRolloverLoanMock commitmentRolloverLoan;
    TellerV2SolMock tellerV2;
    WethMock wethMock;
    LenderCommitmentForwarderMock lenderCommitmentForwarder ;
    //MarketRegistryMock marketRegistryMock;

    function setUp() public {

        borrower = new User();
        lender = new User();

        tellerV2 = new TellerV2SolMock();
        wethMock = new WethMock();

        lenderCommitmentForwarder = new LenderCommitmentForwarderMock();


        wethMock.deposit{value:100e18}();
        wethMock.transfer(address(lender),5e18);
        wethMock.transfer(address(borrower),5e18);
        wethMock.transfer(address(lenderCommitmentForwarder),5e18);

        //marketRegistryMock = new MarketRegistryMock();

       
        commitmentRolloverLoan = new CommitmentRolloverLoanMock(
            address(tellerV2), address(lenderCommitmentForwarder)
        );


    }
 

    function test_rolloverLoan() public {
 
         address lendingToken = address(wethMock);
         uint256 marketId = 0;
         uint256 principalAmount = 500;
         uint32 duration = 10 days;
         uint16 interestRate = 100;

         ILenderCommitmentForwarder.Commitment memory commitment = ILenderCommitmentForwarder.Commitment({
            maxPrincipal: principalAmount,
            expiration: uint32(block.timestamp + 1 days),
            maxDuration: duration,
            minInterestRate: interestRate, 
            collateralTokenAddress: address(0), 
            collateralTokenId: 0 , 
            maxPrincipalPerCollateralAmount: 0, 
            collateralTokenType: ILenderCommitmentForwarder.CommitmentCollateralType.NONE, 
            lender: address(lender) , 
            marketId: marketId, 
            principalTokenAddress: lendingToken 
         });

         lenderCommitmentForwarder.setCommitment(0,commitment);

         ICommitmentRolloverLoan.AcceptCommitmentArgs memory commitmentArgs = ICommitmentRolloverLoan.AcceptCommitmentArgs({
            commitmentId: 0,
            principalAmount: principalAmount,
            collateralAmount: 100,
            collateralTokenId: 0,
            collateralTokenAddress: address(0),
            interestRate: interestRate,
            loanDuration: duration
         });

        vm.prank(address(borrower));
        uint256 loanId = tellerV2.submitBid( 
            lendingToken,
            marketId,
            principalAmount,
            duration,
            interestRate,
            "",
            address(borrower)
         );

        uint256 rolloverAmount = 0; 

        //fix me here -- tellerv2 needs to accept bid to put it in correct state
        vm.prank(address(borrower));
        
        commitmentRolloverLoan.rolloverLoan(
            loanId,
            rolloverAmount,
            commitmentArgs
        );
 

        bool acceptCommitmentWithRecipientWasCalled = lenderCommitmentForwarder.acceptCommitmentWithRecipientWasCalled();
        assertTrue(acceptCommitmentWithRecipientWasCalled,"acceptCommitmentWithRecipient not called");
    }


     /*function test_rolloverLoan_should_revert_if_loan_not_accepted() public {
 

         address lendingToken = address(wethMock);
         uint256 marketId = 0;
         uint256 principalAmount = 500;
         uint32 duration = 10 days;
         uint16 interestRate = 100;

         ICommitmentRolloverLoan.AcceptCommitmentArgs memory commitmentArgs = ICommitmentRolloverLoan.AcceptCommitmentArgs({
            commitmentId: 0,
            principalAmount: principalAmount,
            collateralAmount: 100,
            collateralTokenId: 0,
            collateralTokenAddress: address(0),
            interestRate: interestRate,
            loanDuration: duration
         });

        vm.prank(address(borrower));
        uint256 loanId = tellerV2.submitBid( 
            lendingToken,
            marketId,
            principalAmount,
            duration,
            interestRate,
            "",
            address(borrower)
         );


        
        vm.prank(address(borrower));
        vm.expectRevert();
        commitmentRolloverLoan.rolloverLoan(
            loanId,
            commitmentArgs
        );
        
    }*/
  

  /*
    scenario A - user needs to pay 0.1weth + 1 weth to the lender. they will get 0.5weth - 0.05 weth = 0.45 weth from the rollover to paybackthe user.  rest 0.65 needs to be paid back by the borrower.abi
    Scenario B - user needs to pay 0.1weth + 1 weth back to the lender. They will get 1.2weth - 0.12weth = 1.08 weth from the rollover to pay back the user so 0.02 needs to be paid back to the borrower.abi
    Scenario C - user needs to pay 0.1 weth + 1 weth back to the lender.  They will get 2 weth - 0.2 weth = 1.8weth so 0.6 weth is given to the borrower .  

    assume that 10 pct fee is taken by pool plus protocol for simplicity. 



  */

  function test_rolloverLoan_financial_scenario_A() public {

        address lendingToken = address(wethMock);

        //initial loan - need to pay back 1 weth + 0.1 weth (interest) to the lender 
         uint256 marketId = 0;
         uint256 principalAmount =  1e18;
         uint32 duration = 36 days;
         uint16 interestRate = 100;

         
        vm.prank(address(borrower));
        uint256 loanId = tellerV2.submitBid( 
            lendingToken,
            marketId,
            principalAmount,
            duration,
            interestRate,
            "",
            address(borrower)
         );

        vm.prank(address(lender));
        wethMock.approve(address(tellerV2),1e18);

        vm.prank(address(lender));
        (uint256 amountToProtocol,
        uint256 amountToMarketplace,
        uint256 amountToBorrower) 
        = tellerV2.lenderAcceptBid( 
            loanId  
         );

        vm.warp(36 days); 

        ILenderCommitmentForwarder.Commitment memory commitment = ILenderCommitmentForwarder.Commitment({
            maxPrincipal: principalAmount,
            expiration: uint32(block.timestamp + 1 days),
            maxDuration: duration,
            minInterestRate: interestRate, 
            collateralTokenAddress: address(0), 
            collateralTokenId: 0 , 
            maxPrincipalPerCollateralAmount: 0, 
            collateralTokenType: ILenderCommitmentForwarder.CommitmentCollateralType.NONE, 
            lender: address(lender) , 
            marketId: marketId, 
            principalTokenAddress: lendingToken 
         });

         lenderCommitmentForwarder.setCommitment(0,commitment);

        //should get 0.5 weth (0.45 after fees) from accepting this commitment  during the rollover process
        uint256 commitmentPrincipalAmount = 2 * 1e18; //2 weth 
        ICommitmentRolloverLoan.AcceptCommitmentArgs memory commitmentArgs = ICommitmentRolloverLoan.AcceptCommitmentArgs({
            commitmentId: 0, 
            principalAmount: commitmentPrincipalAmount,
            collateralAmount: 0,
            collateralTokenId: 0,
            collateralTokenAddress: address(0),
            interestRate: interestRate,
            loanDuration: duration
         });

        uint256 rolloverAmount = 65 * 1e16; //0.65 weth 

        uint256 borrowerBalanceBeforeRollover = wethMock.balanceOf(address(borrower));

        vm.prank(address(borrower));
        wethMock.approve(address(commitmentRolloverLoan), rolloverAmount);


        vm.prank(address(borrower));
        
        // need to pay 0.65 weth as the borrower ! 
        uint256 _newLoanId =  commitmentRolloverLoan.rolloverLoan(
            loanId,
            rolloverAmount,
            commitmentArgs
        );
 
      uint256 borrowerBalanceAfterRollover = wethMock.balanceOf(address(borrower));

        
        assertEq(borrowerBalanceBeforeRollover - borrowerBalanceAfterRollover , 65 * 1e16, "incorrect balance after rollover");

  }
  


  function test_rolloverLoan_financial_scenario_C() public {

        address lendingToken = address(wethMock);

        //initial loan - need to pay back 1 weth + 0.1 weth (interest) to the lender 
         uint256 marketId = 0;
         uint256 principalAmount =  1e18;
         uint32 duration = 36 days;
         uint16 interestRate = 100;

         
        vm.prank(address(borrower));
        uint256 loanId = tellerV2.submitBid( 
            lendingToken,
            marketId,
            principalAmount,
            duration,
            interestRate,
            "",
            address(borrower)
         );

        vm.prank(address(lender));
        wethMock.approve(address(tellerV2),1e18);

        vm.prank(address(lender));
        (uint256 amountToProtocol,
        uint256 amountToMarketplace,
        uint256 amountToBorrower) 
        = tellerV2.lenderAcceptBid( 
            loanId  
         );

        vm.warp(36 days); 


          ILenderCommitmentForwarder.Commitment memory commitment = ILenderCommitmentForwarder.Commitment({
            maxPrincipal: principalAmount,
            expiration: uint32(block.timestamp + 1 days),
            maxDuration: duration,
            minInterestRate: interestRate, 
            collateralTokenAddress: address(0), 
            collateralTokenId: 0 , 
            maxPrincipalPerCollateralAmount: 0, 
            collateralTokenType: ILenderCommitmentForwarder.CommitmentCollateralType.NONE, 
            lender: address(lender) , 
            marketId: marketId, 
            principalTokenAddress: lendingToken 
         });

         lenderCommitmentForwarder.setCommitment(0,commitment);

        //should get 2.0 weth   from accepting this commitment  during the rollover process
        uint256 commitmentPrincipalAmount = 2 * 1e18; //2 weth 
        ICommitmentRolloverLoan.AcceptCommitmentArgs memory commitmentArgs = ICommitmentRolloverLoan.AcceptCommitmentArgs({
            commitmentId: 0, 
            principalAmount: commitmentPrincipalAmount,
            collateralAmount: 0,
            collateralTokenId: 0,
            collateralTokenAddress: address(0),
            interestRate: interestRate,
            loanDuration: duration
         });

        uint256 rolloverAmount = 0;   

        uint256 borrowerBalanceBeforeRollover = wethMock.balanceOf(address(borrower));

        vm.prank(address(borrower));
        wethMock.approve(address(commitmentRolloverLoan), rolloverAmount);


        vm.prank(address(borrower));
        
        // need to pay 0.65 weth as the borrower ! 
        uint256 _newLoanId =  commitmentRolloverLoan.rolloverLoan(
            loanId,
            rolloverAmount,
            commitmentArgs
        );
 
 //neeed the roolover to really move tokens around !
       uint256 borrowerBalanceAfterRollover = wethMock.balanceOf(address(borrower));

        
      assertEq( borrowerBalanceAfterRollover  - borrowerBalanceBeforeRollover, 60 * 1e16, "incorrect balance after rollover");

  }
  

}

contract User {}
