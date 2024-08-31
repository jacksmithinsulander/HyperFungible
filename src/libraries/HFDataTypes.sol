// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.26;

library HFDataTypes{
    enum CcipFeesIn {
        NATIVE,
        LINK
    }

    struct HyperfyOrder{
        address tokenAddress;
        uint32 chainId;
        uint256 amount; 
    }
}