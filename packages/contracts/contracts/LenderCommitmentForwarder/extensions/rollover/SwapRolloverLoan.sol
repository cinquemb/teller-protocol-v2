// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
 
import "./SwapRolloverLoan_G1.sol";

contract SwapRolloverLoan is SwapRolloverLoan_G1 {
    constructor(
        address _tellerV2, 
        address _factory,
        address _WETH9
    )
        SwapRolloverLoan_G1(
            _tellerV2,
            _factory,
            _WETH9
        )
    {}
}
