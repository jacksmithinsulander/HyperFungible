// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.26;

library HFDataTypes {
    enum CcipFeesIn {
        NATIVE,
        LINK
    }

    struct HyperfyOrder {
        address token;
        uint256 amount; 
    }

    struct FullOrder {
        HyperfyOrder order;
        uint40 chainId;
    }

    struct NavVals {
        uint40 chainId;
        address token;
    }
}