// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.26;

/* Chainlink Libraries */
import {Client} from "@chainlink/contracts/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/ccip/applications/CCIPReceiver.sol";

/* Chainlink Interfaces */
import {IRouterClient} from "@chainlink/contracts/ccip/interfaces/IRouterClient.sol";
//import {LinkTokenInterface} from "@chainlink/contracts/";

/* OpenZeppelin Interfaces */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* HyperFungible Libraries */
import {HFDataTypes} from "src/libraries/HFDataTypes.sol";

contract HyperFungible is CCIPReceiver {

    HFDataTypes.CcipFeesIn public ccipFeesIn;
    address public ccipRouter;
    address public link;
    uint32 public chainId;
    mapping(uint64 destinations => address receiver) public receiverOnChain;

    constructor (address _ccipRouter, address _link, uint32 _chainId) {
        ccipFeesIn = HFDataTypes.CcipFeesIn.NATIVE;
        ccipRouter = _ccipRouter;
        link = _link;
        chainId = _chainId;
    }

    function hyperfyTokens(HFDataTypes.HyperfyOrder _order, uint64 _destination) external returns(bytes32 _messageId) {
        IERC20(_order.token).transferFrom(msg.sender, address(this), _order.amount);

        IRouterClient router = IRouterClient(ccipRouter);

        HFDataTypes.FullOrder memory fullOrder = HFDataTypes.FullOrder({
            order: _order,
            chainId: chainId
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverOnChain[_destination]),
            data: abi.encode(fullOrder),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: ccipFeesIn == DataTypes.CcipFeesIn.LINK ? link : address(0)
        });

        uint256 fees = router.getFee(destination, message);

        _messageId = router.ccipSend{value: fees}(
            destination,
            message
        );
    }
}
