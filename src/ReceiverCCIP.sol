// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {
    EigenlayerDeposit6551Message,
    EigenlayerDepositWithSignatureMessage,
    TransferToStakerMessage
} from "./interfaces/IEigenlayerMsgDecoders.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "./interfaces/IReceiverCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";

import {BaseSepolia} from "../script/Addresses.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";

import {console} from "forge-std/Test.sol";


/// ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them.
contract ReceiverCCIP is BaseMessengerCCIP {

    IRestakingConnector public restakingConnector;
    address public senderContractL2Addr;

    IERC6551Registry public erc6551Registry;
    EigenAgentOwner721 public eigenAgentOwner721;

    mapping(address => uint256) public userToEigenAgentOwnerTokenIds;
    mapping(address => address) public userToEigenAgents;

    error InvalidContractAddress(string msg);

    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(address _router, address _link) BaseMessengerCCIP(_router, _link) {}

    function initialize(
        IRestakingConnector _restakingConnector,
        ISenderCCIP _senderContractL2,
        IERC6551Registry _erc6551Registry,
        EigenAgentOwner721 _eigenAgentOwner721
    ) initializer public {

        if (address(_restakingConnector) == address(0))
            revert InvalidContractAddress("restakingConnector cannot be address(0)");

        if (address(_senderContractL2) == address(0))
            revert InvalidContractAddress("SenderCCIP cannot be address(0)");

        if (address(_erc6551Registry) == address(0))
            revert InvalidContractAddress("ERC6551Registry cannot be address(0)");

        if (address(_eigenAgentOwner721) == address(0))
            revert InvalidContractAddress("EigenAgentOwner721 cannot be address(0)");

        restakingConnector = _restakingConnector;
        senderContractL2Addr = address(_senderContractL2);

        erc6551Registry = _erc6551Registry;
        eigenAgentOwner721 = _eigenAgentOwner721;

        BaseMessengerCCIP.__BaseMessengerCCIP_init();
    }

    /// Mints an NFT and creates a 6551 account for it
    function _spawnEigenAgent6551(address staker) internal returns (EigenAgent6551) {
        require(
            userToEigenAgentOwnerTokenIds[staker] == 0,
            "staker already has an EigenAgentOwner NFT"
        );
        require(
            userToEigenAgents[staker] == address(0),
            "staker already has an EigenAgent account"
        );

        bytes32 salt = bytes32(abi.encode(staker));
        uint256 tokenId = eigenAgentOwner721.mint(staker);

        EigenAgent6551 eigenAgentImpl = new EigenAgent6551();

        EigenAgent6551 eigenAgent = EigenAgent6551(payable(
            erc6551Registry.createAccount(
                address(eigenAgentImpl),
                salt,
                block.chainid,
                address(eigenAgentOwner721),
                tokenId
            )
        ));

        userToEigenAgentOwnerTokenIds[staker] == tokenId;
        userToEigenAgents[staker] = address(eigenAgent);

        return eigenAgent;
    }

    function spawnEigenAgentOnlyOwner(address staker) external onlyOwner returns (EigenAgent6551) {
        return _spawnEigenAgent6551(staker);
    }

    function _getEigenAgent(address staker) internal returns (EigenAgent6551) {
        EigenAgent6551 eigenAgent = EigenAgent6551(payable(userToEigenAgents[staker]));
        if (address(eigenAgent) == address(0)) {
            return _spawnEigenAgent6551(staker);
        }
        return eigenAgent;
    }

    function getSenderContractL2Addr() public view returns (address) {
        // address, contract only exists on L2
        return senderContractL2Addr;
    }

    function setSenderContractL2Addr(address _senderContractL2) public onlyOwner {
        senderContractL2Addr = _senderContractL2;
    }

    function getRestakingConnector() public view returns (IRestakingConnector) {
        return restakingConnector;
    }

    function setRestakingConnector(IRestakingConnector _restakingConnector) public onlyOwner {
        restakingConnector = _restakingConnector;
    }

    function mockCCIPReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) public {
        _ccipReceive(any2EvmMessage);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
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
        bytes4 functionSelector = restakingConnector.decodeFunctionSelector(message);

        (
            IDelegationManager delegationManager,
            IStrategyManager strategyManager,
            IStrategy strategy
        ) = restakingConnector.getEigenlayerContracts();

        string memory textMsg = "no matching functionSelector";
        uint256 amountMsg = s_lastReceivedTokenAmount;


        if (functionSelector == 0x76fa57a5) {
            // bytes4(keccak256("deposit6551(address,address,uint256,address,uint256,bytes)")) == 0x76fa57a5
            EigenlayerDeposit6551Message memory eigenMsg = restakingConnector.decodeDeposit6551Message(message);
            EigenAgent6551 eigenAgent = _getEigenAgent(eigenMsg.staker);
            // console.log("eigenAgent:", address(eigenAgent));
            // console.log("strategy:", address(eigenMsg.strategy));
            // console.log("amount:", eigenMsg.amount);
            // console.logBytes(eigenMsg.signature);

            address token = any2EvmMessage.destTokenAmounts[0].token; // CCIP-BnM token on L1

            bytes memory data2 = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
                address(strategy),
                token,
                eigenMsg.amount
            );

            // eigenAgent approves StrategyManager using DepositIntoStrategy signature
            eigenAgent.approveStrategyManagerWithSignature(
                address(strategyManager), // strategyManager
                0,
                data2, // encodeDepositIntoStrategyMsg
                eigenMsg.expiry,
                eigenMsg.signature
            );

            IERC20(token).transfer(address(eigenAgent), eigenMsg.amount);

            bytes memory result = eigenAgent.executeWithSignature(
                address(strategyManager), // strategyManager
                0,
                data2, // encodeDepositIntoStrategyMsg
                eigenMsg.expiry,
                eigenMsg.signature
            );

            textMsg = "approve and deposited via 6551 agent";
        }

        if (functionSelector == 0x32e89ace) {
            // bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")) == 0x32e89ace
            EigenlayerDepositWithSignatureMessage memory eigenMsg;
            eigenMsg = restakingConnector.decodeDepositWithSignatureMessage(message);

            IERC20 underlyingToken = strategy.underlyingToken();
            // Receiver contract approves eigenlayer StrategyManager for deposits
            underlyingToken.approve(address(strategyManager), eigenMsg.amount);
            // deposit into Eigenlayer with user signature
            strategyManager.depositIntoStrategyWithSignature(
                IStrategy(eigenMsg.strategy),
                IERC20(eigenMsg.token),
                eigenMsg.amount,
                eigenMsg.staker,
                eigenMsg.expiry,
                eigenMsg.signature
            );
            textMsg = "depositIntoStrategyWithSignature()";
            amountMsg = eigenMsg.amount;
        }

        if (functionSelector == 0x0dd8dd02) {
            // bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),

            IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams =
                restakingConnector.decodeQueueWithdrawalsMessage(message);

            delegationManager.queueWithdrawals(queuedWithdrawalParams);

            textMsg = "queueWithdrawals()";
        }

        if (functionSelector == 0xa140f06e) {
            // bytes4(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])")),

            IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalsWithSigParams =
                restakingConnector.decodeQueueWithdrawalsWithSignatureMessage(message);

            require(queuedWithdrawalsWithSigParams.length > 0, "queuedWithdrawalsWithSigParams: length cannot be 0");

            address staker = queuedWithdrawalsWithSigParams[0].staker;
            // queueWithdrawal uses current nonce in the withdrawalRoot, the increments after
            // so save this nonce before dispatching queueWithdrawalsWithSignature
            uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
            restakingConnector.setQueueWithdrawalBlock(staker, nonce);

            // Call QueueWithdrawalsWithSignature on Eigenlayer
            bytes32[] memory withdrawalRoots = delegationManager.queueWithdrawalsWithSignature(
                queuedWithdrawalsWithSigParams
            );

            textMsg = "queueWithdrawalsWithSignature()";
            amountMsg = queuedWithdrawalsWithSigParams[0].shares[0];
        }

        if (functionSelector == 0x54b2bf29) {
            // bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)")) == 0x54b2bf29
            (
                IDelegationManager.Withdrawal memory withdrawal,
                IERC20[] memory tokensToWithdraw,
                uint256 middlewareTimesIndex,
                bool receiveAsTokens
            ) = restakingConnector.decodeCompleteWithdrawalMessage(message);

            // requires(msg.sender == withdrawal.withdrawer), so only this contract can withdraw
            // since all queuedWithdrawals are also done through this contract.
            // then it calculates withdrawalRoot ensuring staker/withdrawal/block is a valid withdrawal.
            delegationManager.completeQueuedWithdrawal(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            // address original_staker = withdrawal.staker;
            uint256 amount = withdrawal.shares[0];
            // Approve L1 receiverContract to send ccip-BnM tokens to Router
            IERC20 token = withdrawal.strategies[0].underlyingToken();
            token.approve(address(this), amount);

            string memory text_message = string(restakingConnector.encodeTransferToStakerMsg(withdrawalRoot));

            /// return token to staker via bridge with message to transferToStaker
            this.sendMessagePayNative(
                BaseSepolia.ChainSelector, // destination chain
                senderContractL2Addr,
                text_message,
                address(token), // L1 token address to burn/lock
                amount
            );

            // textMsg = "completeQueuedWithdrawal()";
            textMsg = text_message;
        }

        if (functionSelector == 0x7f548071) {
            // bytes4(keccak256("delegateToBySignature(address,address,(bytes,uint256),(bytes,uint256),bytes32)")) == 0x7f548071
            (
                address staker,
                address operator,
                ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry,
                ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
                bytes32 approverSalt
            ) = restakingConnector.decodeDelegateToBySignature(message);

            delegationManager.delegateToBySignature(
                staker,
                operator,
                stakerSignatureAndExpiry,
                approverSignatureAndExpiry,
                approverSalt
            );
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            textMsg,
            s_lastReceivedTokenAddress,
            amountMsg
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

        bytes4 functionSelector = restakingConnector.decodeFunctionSelector(message);
        uint256 gasLimit = 600_000;

        if (functionSelector == 0x27167d10) {
            // bytes4(keccak256("transferToStaker(bytes32)")) == 0x27167d10
            gasLimit = 800_000;
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

