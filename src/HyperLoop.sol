// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.26;

/* Chainlink Libraries */
import {Client} from "@chainlink/contracts/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/ccip/applications/CCIPReceiver.sol";

/* Chainlink Interfaces */
import {IRouterClient} from "@chainlink/contracts/ccip/interfaces/IRouterClient.sol";

/* OpenZeppelin Interfaces */
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* HyperFungible Libraries */
import {HFDataTypes} from "src/libraries/HFDataTypes.sol";
import {HFErrors} from "src/libraries/HFErrors.sol";

/* Solady Contracts */
import {ERC20} from "@solady/contracts/tokens/ERC20.sol";

contract HyperLoop is CCIPReceiver {

    HFDataTypes.CcipFeesIn public ccipFeesIn;
    address public ccipRouter;
    address public link;
    uint40 public chainId;

    mapping(uint64 destinations => address receiver) public receiverOnChain;
    mapping(address holder => mapping(uint40 chainId => mapping(address token => uint256 amount))) public hftBalanceOf;
    mapping(address holder => bytes hashed) public nextSpendable;
    mapping(address holder => bytes[] hashed) public hftHashesOf;
    mapping(address holder => mapping(bytes hashed => bool status)) private hasHft;
    mapping(uint40 chainid => uint64 ccipDestinationId) private ccipIdOf;

    constructor (address _ccipRouter, address _link, uint40 _chainId) CCIPReceiver(_ccipRouter) {
        ccipFeesIn = HFDataTypes.CcipFeesIn.NATIVE;
        ccipRouter = _ccipRouter;
        link = _link;
        chainId = _chainId;

        _instantiateCcipIds();
    }

    function hyperfyTokens(HFDataTypes.HyperfyOrder calldata _order, uint64 _destination) external returns(bytes32 _messageId) {
        IERC20(_order.token).transferFrom(msg.sender, address(this), _order.amount);

        IRouterClient router = IRouterClient(ccipRouter);

        HFDataTypes.FullOrder memory fullOrder = HFDataTypes.FullOrder({
            order: _order,
            chainId: chainId,
            to: msg.sender
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverOnChain[_destination]),
            data: abi.encode(fullOrder),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: ccipFeesIn == HFDataTypes.CcipFeesIn.LINK ? link : address(0)
        });

        uint256 fees = router.getFee(_destination, message);

        _messageId = router.ccipSend{value: fees}(
            _destination,
            message
        );
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        HFDataTypes.HyperLoopReturn memory hlr = _decodeHyperLoop(message.data);

        IERC20(hlr.token).transfer(hlr.to, hlr.amount);
    }

    function _decodeHyperLoop(bytes memory hashed) internal pure returns (HFDataTypes.HyperLoopReturn memory _hyperLoop) {
        _hyperLoop = abi.decode(hashed, (HFDataTypes.HyperLoopReturn));
    }

    function _instantiateCcipIds() internal {
        ccipIdOf[11155111] = 16015286601757825753;
        ccipIdOf[84532] = 10344971235874465080;
        ccipIdOf[43113] = 14767482510784806043;
    }
}