// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.26;

library HFErrors {

    error NO_NEXT_TOKEN_AND_PROBABLY_NOT_A_HYPER_FUNGIBLE_TOKEN_HOLDER_WHAT_THE_FUCK();

    error YOU_DONT_HOLD_THIS_MUCH(uint40 chainId, address token);

}