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

    constructor (address _ccipRouter, address _link, uint40 _chainId) CCIPReceiver(_ccipRouter) {
        ccipFeesIn = HFDataTypes.CcipFeesIn.NATIVE;
        ccipRouter = _ccipRouter;
        link = _link;
        chainId = _chainId;
    }

    function hyperfyTokens(HFDataTypes.HyperfyOrder calldata _order, uint64 _destination) external returns(bytes32 _messageId) {
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
            feeToken: ccipFeesIn == HFDataTypes.CcipFeesIn.LINK ? link : address(0)
        });

        uint256 fees = router.getFee(_destination, message);

        _messageId = router.ccipSend{value: fees}(
            _destination,
            message
        );
    }

    function name() external view override returns(string memory) {
        return "HyperFungibleToken";
    }

    function symbol() external view override returns(string memory) {
        return "HFT";
    }

    function _afterMint(address _to, uint256 _amount) internal {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[_to]);
        hftBalanceOf[_to][navVals.chainId][navVals.token] = _amount;

        if (!hasHft[to][nextSpendable[msg.sender]]) {
            hftHashesOf[to].push = nextSpendable[msg.sender];

            hasHft[to][nextSpendable[msg.sender]] = true;
        }

    }

    function _afterBurn(address _from, uint256 _amount) internal {}

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        HFDataTypes.FullOrder memory receivedMessage = _decodeMessage(message.data);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        if (!nextSpendable[msg.sender]) revert HFErrors.NO_NEXT_TOKEN_AND_PROBABLY_NOT_A_HYPER_FUNGIBLE_TOKEN_HOLDER_WHAT_THE_FUCK();
        if (amount > hftBalanceOf[msg.sender][navVals.chainId][navVals.token]) revert HFErrors.YOU_DONT_HOLD_THIS_MUCH(navVals.chainId, navVals.token);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        HFDataTypes.NavVals memory navVals = _decodeNavVals(nextSpendable[msg.sender]);

        bool senderEmptied;

        if (amount == hftBalanceOf[msg.sender][navVals.chainId][navVals.token]) {
            hftBalanceOf[msg.sender][navVals.chainId][navVals.token] = 0;
            senderEmptied = true;
            hftBalanceOf[to][navVals.chainId][navVals.token] = amount;
        } else {
            hftBalanceOf[msg.sender][navVals.chainId][navVals.token] -= amount;
            hftBalanceOf[to][navVals.chainId][navVals.token] += amount;
        }

        if (!hasHft[to][nextSpendable[msg.sender]]) {
            hftHashesOf[to].push = nextSpendable[msg.sender];

            hasHft[to][nextSpendable[msg.sender]] = true;
        }

        if (senderEmptied) {
            for (uint i = 0; i < hftHashesOf[msg.sender].lenth; i++) {
                if (hftHashesOf[msg.sender][i] == nextSpendable[msg.sender]) {
                    hashHft[msg.sender][nextSpendable[msg.sender]] = false;
                    delete hftHashesOf[msg.sender][i];
                    delete nextSpendable[msg.sender];
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
}
