// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {BaseSepolia} from "../script/Addresses.sol";


/// @title ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them
contract ReceiverCCIP is Initializable, BaseMessengerCCIP {

    IRestakingConnector public restakingConnector;
    address public senderContractL2;

    error AddressZero(string msg);

    event BridgingWithdrawalToL2(
        address indexed senderContractL2,
        bytes32 indexed withdrawalAgentOwnerRoot,
        uint256 indexed withdrawalAmount
    );

    /// @param _router address of the router contract.
    /// @param _link address of the link contract.
    constructor(address _router, address _link) BaseMessengerCCIP(_router, _link) {
        _disableInitializers();
    }

    /// @param _restakingConnector address of the restakingConnector contract.
    /// @param _senderContractL2 address of the senderCCIP contract on L2
    function initialize(
        IRestakingConnector _restakingConnector,
        ISenderCCIP _senderContractL2
    ) initializer public {

        if (address(_restakingConnector) == address(0))
            revert AddressZero("RestakingConnector cannot be address(0)");

        if (address(_senderContractL2) == address(0))
            revert AddressZero("SenderCCIP cannot be address(0)");

        restakingConnector = _restakingConnector;
        senderContractL2 = address(_senderContractL2);

        BaseMessengerCCIP.__BaseMessengerCCIP_init();
    }

    function getSenderContractL2Addr() public view returns (address) {
        return senderContractL2;
    }

    function setSenderContractL2Addr(address _senderContractL2) public onlyOwner {
        if (address(_senderContractL2) == address(0))
            revert AddressZero("SenderContract on L2 cannot be address(0)");

        senderContractL2 = _senderContractL2;
    }

    function getRestakingConnector() public view returns (IRestakingConnector) {
        return restakingConnector;
    }

    function setRestakingConnector(IRestakingConnector _restakingConnector) public onlyOwner {
        if (address(_restakingConnector) == address(0))
            revert AddressZero("RestakingConnector cannot be address(0)");

        restakingConnector = _restakingConnector;
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

        string memory textMsg = "no matching Eigenlayer functionSelector";
        //////////////////////////////////
        // Deposit Into Strategy
        //////////////////////////////////
        if (functionSelector == IStrategyManager.depositIntoStrategy.selector) {
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa

            IERC20(token).approve(address(restakingConnector), amount);
            // approve RestakingConnector to transfer tokens to EigenAgent
            restakingConnector.depositWithEigenAgent(message);

            textMsg = "Deposited by EigenAgent";
        }

        //////////////////////////////////
        // Mint EigenAgent
        //////////////////////////////////
        if (functionSelector == IRestakingConnector.mintEigenAgent.selector) {
            // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
            restakingConnector.mintEigenAgent(message);
            textMsg = "called mintEigenAgent";
        }

        //////////////////////////////////
        // Queue Withdrawals
        //////////////////////////////////
        if (functionSelector == IDelegationManager.queueWithdrawals.selector) {
            // cast sig "queueWithdrawals((address[],uint256[],address)[])" == 0x0dd8dd02
            restakingConnector.queueWithdrawalsWithEigenAgent(message);

            textMsg = "Withdrawal queued by EigenAgent";
        }

        //////////////////////////////////
        // Complete Withdrawal
        //////////////////////////////////
        if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed

            (
                bool receiveAsTokens,
                uint256 withdrawalAmount,
                address withdrawalToken,
                string memory messageForL2,
                bytes32 withdrawalAgentOwnerRoot
            ) = restakingConnector.completeWithdrawalWithEigenAgent(message);

            if (receiveAsTokens) {
                /// if `receiveAsTokens == true`, ReceiverCCIP should have received tokens
                /// back from EigenAgent after completeWithdrawal
                ///
                /// Send handleTransferToAgentOwner message to bridge tokens back to L2.
                /// L2 SenderCCIP transfers tokens to AgentOwner.
                this.sendMessagePayNative(
                    BaseSepolia.ChainSelector, // destination chain
                    senderContractL2,
                    messageForL2,
                    withdrawalToken, // L1 token to burn/lock
                    withdrawalAmount,
                    0 // use default gasLimit for
                );

                emit BridgingWithdrawalToL2(
                    senderContractL2,
                    withdrawalAgentOwnerRoot,
                    withdrawalAmount
                );

                textMsg = "Complete Queued Withdrawal by EigenAgent";
            } else {
                /// Otherwise if `receiveAsTokens == false`, withdrawal is redeposited in Eigenlayer
                /// as shares, re-delegated to a new Operator as part of the `undelegate` flow.
                /// We do not need to do anything in thise case.
            }
        }

        //////////////////////////////////
        // delegateTo
        //////////////////////////////////
        if (functionSelector == IDelegationManager.delegateTo.selector) {

            restakingConnector.delegateToWithEigenAgent(message);

            textMsg = "Delegated to Operator by EigenAgent";
        }

        //////////////////////////////////
        // undelegate
        //////////////////////////////////
        if (functionSelector == IDelegationManager.undelegate.selector) {

            restakingConnector.undelegateWithEigenAgent(message);

            textMsg = "Undelegated by EigenAgent";
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
    /// @param _overrideGasLimit set the gaslimit manually. If 0, uses default gasLimits.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        uint256 _overrideGasLimit
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
        if (_overrideGasLimit > 0) {
            gasLimit = _overrideGasLimit;
        }

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

