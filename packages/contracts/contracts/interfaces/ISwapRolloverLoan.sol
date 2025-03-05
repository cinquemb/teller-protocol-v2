// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISwapRolloverLoan {
    struct RolloverCallbackArgs {
        address lenderCommitmentForwarder;
        uint256 loanId;
        address borrower;
        uint256 borrowerAmount;
        address rewardRecipient;
        uint256 rewardAmount;
        bytes acceptCommitmentArgs;
    }
}
