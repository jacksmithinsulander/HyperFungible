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

    function withdrawTokens(uint256 _amount) external {
        HFTDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[_msg.sender]);

        if (_amount > hftBalanceOf[_to][navVals.chainId][navVals.token]) revert HFErrors.YOU_DONT_HOLD_THIS_MUCH(navVals.chainId, navVals.token);

        IRouterClient router = IRouterClient(ccipRouter);

        HFDataTypes.HyperLoopReturn memory hyperLoopReturn = HFDataTypes.HyperLoopReturn({
            to: msg.sender,
            token: navVals.token,
            amount: hftBalanceOf[_to][navVals.chainId][navVals.token]
        });

        uint64 destination = ccipIdOf[navVals.chainId];

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverOnChain[_destination]),
            data: abi.encode(hyperLoopReturn),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: ccipFeesIn == HFDataTypes.CcipFeesIn.LINK ? link : address(0)
        });

        uint256 fees = router.getFee(_destination, message);

        _messageId = router.ccipSend{value: fees}(
            _destination,
            message
        );

        _burn(msg.sender, _amount);
    }

    function name() external view override returns(string memory) {
        return "HyperFungibleToken";
    }

    function symbol() external view override returns(string memory) {
        return "HFT";
    }

    function getHftHashesOf(address _user) external view returns (bytes[] memory _hftHashes) {
        _hftHashes = hftHashsOf[_user];
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

        if (!hasHft[to][nextSpendable[_to]]) {
            hftHashesOf[to].push = nextSpendable[_to];

            hasHft[to][nextSpendable[_to]] = true;
        }

    }

    function _afterBurn(address _from, uint256 _amount) internal {
        HFDataTypes memory navVals = _decodeNavVals(nextSpendable[_from]);

        if (_amount == hftBalanceOf[_from][navVals.chainId][navVals.token]) {
            hftBalanceOf[from][navVals.chainId][navVals.token] = 0;
            hashHft[from][nextSpendable[from]] = false;
            for (uint i = 0; i < hftHashesOf[from].lenth; i++) {
                if (hftHashesOf[from][i] == nextSpendable[from]) {
                    hashHft[from][nextSpendable[from]] = false;
                    delete hftHashesOf[from][i];
                    delete nextSpendable[from];
                }
            }
        } else {
            hftBalanceOf[from][navVals.chainId][navVals.token] -= _amount;
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        HFDataTypes.FullOrder memory receivedMessage = _decodeMessage(message.data);

        HFDataTypes.NavVals memory navVals = (HFDataTypes.NavVals({
            chainId: receivedMessage.chainId;
            token: receivedMessage.order.token;
        });

        bytes memory spendableHash = abi.encode(navVals);

        nextSpendable[received.to] = spendableHash;

        _mint(received.to, received.order.amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (!nextSpendable[from]) revert HFErrors.NO_NEXT_TOKEN_AND_PROBABLY_NOT_A_HYPER_FUNGIBLE_TOKEN_HOLDER_WHAT_THE_FUCK();
        if (amount > hftBalanceOf[from][navVals.chainId][navVals.token]) revert HFErrors.YOU_DONT_HOLD_THIS_MUCH(navVals.chainId, navVals.token);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[from]);

        bool senderEmptied;

        if (amount == hftBalanceOf[from][navVals.chainId][navVals.token]) {
            hftBalanceOf[from][navVals.chainId][navVals.token] = 0;
            hashHft[from][nextSpendable[from]] = false;
            senderEmptied = true;
            hftBalanceOf[to][navVals.chainId][navVals.token] = amount;
        } else {
            hftBalanceOf[from][navVals.chainId][navVals.token] -= amount;
            hftBalanceOf[to][navVals.chainId][navVals.token] += amount;
        }

        if (!hasHft[to][nextSpendable[from]]) {
            hftHashesOf[to].push = nextSpendable[from];

            hasHft[to][nextSpendable[from]] = true;
        }

        if (senderEmptied) {
            for (uint i = 0; i < hftHashesOf[from].lenth; i++) {
                if (hftHashesOf[from][i] == nextSpendable[from]) {

                    delete hftHashesOf[from][i];
                    delete nextSpendable[from];
                }
            }
        }
    }

    function _burn(address from, uint256 amount) internal override {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, from)
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Subtract and store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, sub(sload(_TOTAL_SUPPLY_SLOT), amount))
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }

        _afterBurn(from, amount);
    }

    function _mint(address to, uint256 amount) internal override {
        /// @solidity memory-safe-assembly
        assembly {
            let totalSupplyBefore := sload(_TOTAL_SUPPLY_SLOT)
            let totalSupplyAfter := add(totalSupplyBefore, amount)
            // Revert if the total supply overflows.
            if lt(totalSupplyAfter, totalSupplyBefore) {
                mstore(0x00, 0xe5cfe957) // `TotalSupplyOverflow()`.
                revert(0x1c, 0x04)
            }
            // Store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter)
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, mload(0x0c)))
        }

        _afterMint(to, amount);
    }

    function _decodeMessage(bytes memory _encodedMessage) internal pure returns(HFDataTypes.FullOrder memory _message) {
        _message = abi.decode(_encodedMessage, (HFDataTypes.FullOrder));
    }

    function _decodeNavVals(bytes memory _encodedMessage) internal pure returns(HFDataTypes.NavVals memory _navVals) {
        _navVals = abi.decode(_encodedMessage, (HFDataTypes.NavVals));
    }

    function _instantiateCccipIds() internal {
        ccipIdOf[11155111] = 16015286601757825753;
        ccipIdOf[84532] = 10344971235874465080;
        ccipIdOf[43113] = 14767482510784806043;

        receiverOnChain[11155111] = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;
        receiverOnChain[84532] = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;
        receiverOnChain[43113] = 0xF694E193200268f9a4868e4Aa017A0118C9a8177;
    }
}
