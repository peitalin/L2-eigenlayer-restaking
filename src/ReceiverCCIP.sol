// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";

import {BaseSepolia} from "../script/Addresses.sol";


/// @title ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them
contract ReceiverCCIP is Initializable, BaseMessengerCCIP {

    IRestakingConnector public restakingConnector;
    address public senderContractL2Addr;

    error InvalidContractAddress(string msg);

    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(address _router, address _link) BaseMessengerCCIP(_router, _link) {
        _disableInitializers();
    }

    function initialize(
        IRestakingConnector _restakingConnector,
        ISenderCCIP _senderContractL2
    ) initializer public {

        if (address(_restakingConnector) == address(0))
            revert InvalidContractAddress("restakingConnector cannot be address(0)");

        if (address(_senderContractL2) == address(0))
            revert InvalidContractAddress("SenderCCIP cannot be address(0)");

        restakingConnector = _restakingConnector;
        senderContractL2Addr = address(_senderContractL2);

        BaseMessengerCCIP.__BaseMessengerCCIP_init();
    }

    function getSenderContractL2Addr() public view returns (address) {
        return senderContractL2Addr;
    }

    function setSenderContractL2Addr(address _senderContractL2) public onlyOwner {
        senderContractL2Addr = _senderContractL2;
    }

    function getRestakingConnector() public view returns (IRestakingConnector) {
        return restakingConnector;
    }

    function setRestakingConnector(IRestakingConnector _restakingConnector) public onlyOwner {
        require(address(restakingConnector) != address(0), "cannot set address(0)");
        restakingConnector = _restakingConnector;
    }

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        )
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        if (any2EvmMessage.destTokenAmounts.length > 0) {
            s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
            s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        } else {
            s_lastReceivedTokenAddress = address(0);
            s_lastReceivedTokenAmount = 0;
        }

        bytes memory message = any2EvmMessage.data;
        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);

        address token = s_lastReceivedTokenAddress;
        uint256 amount = s_lastReceivedTokenAmount;
        string memory textMsg = "no matching functionSelector";

        //////////////////////////////////
        // Deposit Into Strategy
        //////////////////////////////////
        if (functionSelector == IRestakingConnector.depositWithEigenAgent.selector) {
            // cast sig "depositWithEigenAgent(bytes,address,uint256)" == 0xaac4ec88
            IERC20(token).approve(address(restakingConnector), amount);
            restakingConnector.depositWithEigenAgent(message, token, amount);
            textMsg = "approved and deposited by EigenAgent";
        }

        //////////////////////////////////
        // Queue Withdrawals
        //////////////////////////////////
        if (functionSelector == IDelegationManager.queueWithdrawals.selector) {
            // cast sig "queueWithdrawals((address[],uint256[],address)[])" == 0x0dd8dd02
            restakingConnector.queueWithdrawalsWithEigenAgent(message);
            textMsg = "withdrawal queued by EigenAgent";
        }

        //////////////////////////////////
        // Complete Withdrawals
        //////////////////////////////////
        if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
            (
                uint256 withdrawalAmount,
                address withdrawalToken,
                string memory messageForL2
            ) = restakingConnector.completeWithdrawalWithEigenAgent(message);

            // Approve L1 receiverContract to send ccip-BnM tokens to Router
            IERC20(withdrawalToken).approve(address(this), withdrawalAmount);

            /// Call bridge with a message to handleTransferToAgentOwner to bridge tokens back to L2
            this.sendMessagePayNative(
                BaseSepolia.ChainSelector, // destination chain
                senderContractL2Addr,
                messageForL2,
                address(withdrawalToken), // L1 token to burn/lock
                amount
            );
            textMsg = "completeQueuedWithdrawal()";
        }

        //////////////////////////////////
        // delegateTo
        //////////////////////////////////
        if (functionSelector == IDelegationManager.delegateTo.selector) {

            restakingConnector.delegateToWithEigenAgent(message);
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            textMsg,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }

    /// @param _receiver The address of the receiver.
    /// @param _text The string data to be sent.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal override returns (Client.EVM2AnyMessage memory) {

        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount <= 0) {
            // Must be an empty array as no tokens are transferred
            // non-empty arrays with 0 amounts error with CannotSendZeroTokens() == 0x5cf04449
            tokenAmounts = new Client.EVMTokenAmount[](0);
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        }

        bytes memory message = abi.encode(_text);

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);
        uint256 gasLimit = restakingConnector.getGasLimitForFunctionSelector(functionSelector);

        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: message,
                tokenAmounts: tokenAmounts,
                feeToken: _feeTokenAddress,
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: gasLimit })
                )
            });
    }

}

