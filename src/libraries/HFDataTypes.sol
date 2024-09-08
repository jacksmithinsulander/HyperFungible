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

    struct HyperLoopReturn {
        address to;
        address token;
        uint256 amount;
    }

    struct FullOrder {
        HyperfyOrder order;
        uint40 chainId;
        address to;
    }

    struct NavVals {
        uint40 chainId;
        address token;
    }
}