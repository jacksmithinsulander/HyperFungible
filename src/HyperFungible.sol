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

contract HyperFungible is CCIPReceiver, ERC20 {

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

    function withdrawTokens(uint256 _amount) external returns (bytes32 _messageId) {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[msg.sender]);

        if (_amount > hftBalanceOf[msg.sender][navVals.chainId][navVals.token]) revert HFErrors.YOU_DONT_HOLD_THIS_MUCH(navVals.chainId, navVals.token);

        IRouterClient router = IRouterClient(ccipRouter);

        HFDataTypes.HyperLoopReturn memory hyperLoopReturn = HFDataTypes.HyperLoopReturn({
            to: msg.sender,
            token: navVals.token,
            amount: hftBalanceOf[msg.sender][navVals.chainId][navVals.token]
        });

        uint64 destination = ccipIdOf[navVals.chainId];

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverOnChain[destination]),
            data: abi.encode(hyperLoopReturn),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: ccipFeesIn == HFDataTypes.CcipFeesIn.LINK ? link : address(0)
        });

        uint256 fees = router.getFee(destination, message);

        _messageId = router.ccipSend{value: fees}(
            destination,
            message
        );

        _burn(msg.sender, _amount);
    }

    function name() public view override returns(string memory) {
        return "HyperFungibleToken";
    }

    function symbol() public view override returns(string memory) {
        return "HFT";
    }

    function getHftHashesOf(address _user) external view returns (bytes[] memory _hftHashes) {
        _hftHashes = hftHashesOf[_user];
    }

    function addReceiverContract(address _receiverContract, uint40 _chainId) external {
        receiverOnChain[ccipIdOf[_chainId]] = _receiverContract;
    }

    function checkIfIHold(bytes memory _hftHash) external view returns (bool _holding, uint256 _amount) {
        _holding = hasHft[msg.sender][_hftHash];

        HFDataTypes.NavVals memory navVals = _decodeNavVals(_hftHash);

        _amount = hftBalanceOf[msg.sender][navVals.chainId][navVals.token];
    }

    function createHftHash(uint40 _chainId, address _token) external pure returns (bytes memory _hftHash) {
        HFDataTypes.NavVals memory navVals = HFDataTypes.NavVals({
            chainId: _chainId,
            token: _token
        });

        _hftHash = abi.encode(navVals);
    }

    function swapNextSpendable(uint40 _chainId, address _token) external {
        HFDataTypes.NavVals memory navVals = HFDataTypes.NavVals({
            chainId: _chainId,
            token: _token
        });
        bytes memory hftHash = abi.encode(navVals);

        if (!hasHft[msg.sender][hftHash]) revert HFErrors.YOU_DONT_OWN_HFT(hftHash);

        nextSpendable[msg.sender] = hftHash;
    }

    function _afterMint(address _to, uint256 _amount) internal {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[_to]);
        hftBalanceOf[_to][navVals.chainId][navVals.token] = _amount;

        if (!hasHft[_to][nextSpendable[_to]]) {
            hftHashesOf[_to].push(nextSpendable[_to]);

            hasHft[_to][nextSpendable[_to]] = true;
        }

    }

    function _afterBurn(address _from, uint256 _amount) internal {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[_from]);

        if (_amount == hftBalanceOf[_from][navVals.chainId][navVals.token]) {
            hftBalanceOf[_from][navVals.chainId][navVals.token] = 0;
            hasHft[_from][nextSpendable[_from]] = false;
            for (uint i = 0; i < hftHashesOf[_from].length; i++) {
                if (keccak256(hftHashesOf[_from][i]) == keccak256(nextSpendable[_from])) {
                    hasHft[_from][nextSpendable[_from]] = false;
                    delete hftHashesOf[_from][i];
                    delete nextSpendable[_from];
                }
            }
        } else {
            hftBalanceOf[_from][navVals.chainId][navVals.token] -= _amount;
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        HFDataTypes.FullOrder memory receivedMessage = _decodeMessage(message.data);

        HFDataTypes.NavVals memory navVals = HFDataTypes.NavVals({
            chainId: receivedMessage.chainId,
            token: receivedMessage.order.token
        });

        bytes memory spendableHash = abi.encode(navVals);

        nextSpendable[receivedMessage.to] = spendableHash;

        _mint(receivedMessage.to, receivedMessage.order.amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (nextSpendable[from].length > 0) revert HFErrors.NO_NEXT_TOKEN_AND_PROBABLY_NOT_A_HYPER_FUNGIBLE_TOKEN_HOLDER_WHAT_THE_FUCK();
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[from]);
        if (amount > hftBalanceOf[from][navVals.chainId][navVals.token]) revert HFErrors.YOU_DONT_HOLD_THIS_MUCH(navVals.chainId, navVals.token);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[from]);

        bool senderEmptied;

        if (amount == hftBalanceOf[from][navVals.chainId][navVals.token]) {
            hftBalanceOf[from][navVals.chainId][navVals.token] = 0;
            hasHft[from][nextSpendable[from]] = false;
            senderEmptied = true;
            hftBalanceOf[to][navVals.chainId][navVals.token] = amount;
        } else {
            hftBalanceOf[from][navVals.chainId][navVals.token] -= amount;
            hftBalanceOf[to][navVals.chainId][navVals.token] += amount;
        }

        if (!hasHft[to][nextSpendable[from]]) {
            hftHashesOf[to].push(nextSpendable[from]);

            hasHft[to][nextSpendable[from]] = true;
        }

        if (senderEmptied) {
            for (uint i = 0; i < hftHashesOf[from].length; i++) {
                if (keccak256(hftHashesOf[from][i]) == keccak256(nextSpendable[from])) {
                    delete hftHashesOf[from][i];
                    delete nextSpendable[from];
                }
            }
        }
    }

    function _decodeMessage(bytes memory _encodedMessage) internal pure returns(HFDataTypes.FullOrder memory _message) {
        _message = abi.decode(_encodedMessage, (HFDataTypes.FullOrder));
    }

    function _decodeNavVals(bytes memory _encodedMessage) internal pure returns(HFDataTypes.NavVals memory _navVals) {
        _navVals = abi.decode(_encodedMessage, (HFDataTypes.NavVals));
    }

    function _instantiateCcipIds() internal {
        ccipIdOf[11155111] = 16015286601757825753;
        ccipIdOf[84532] = 10344971235874465080;
        ccipIdOf[43113] = 14767482510784806043;
    }
}
