// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/ccip/applications/CCIPReceiver.sol";

import {IERC20} from "@openzeppelin-v5-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-v5-contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/access/OwnableUpgradeable.sol";


abstract contract BaseMessengerCCIP is CCIPReceiver, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(uint64 sourceChainSelector => mapping(address sender => bool)) public allowlistedSenders;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */

    uint256[47] private __gap;

    event MessageSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address receiver,
        Client.EVMTokenAmount[] tokenAmounts,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        Client.EVMTokenAmount[] tokenAmounts
    );

    event AllowlistDestinationChain(uint64 indexed destinationChainSelector, bool allowed);
    event AllowlistSourceChain(uint64 indexed sourceChainSelector, bool allowed);
    event AllowlistSender(uint64 indexed sourceChainSelector, address indexed sender, bool allowed);

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error WithdrawalExceedsBalance(uint256 amount, uint256 currentBalance);
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotAllowed(uint64 destinationChainSelector);
    error SourceChainNotAllowed(uint64 sourceChainSelector);
    error SenderNotAllowed(uint64 sourceChainSelector, address sender);
    error InvalidReceiverAddress();
    error NotEnoughEthGasFees(uint256 sentGasFees, uint256 requiredGasFees);
    error FailedToRefundExcessEth(address sender, uint256 refundAmount);
    error CannotSendZeroTokens(address token);

    constructor(address _router) CCIPReceiver(_router) { }

    function __BaseMessengerCCIP_init() internal {
        OwnableUpgradeable.__Ownable_init(msg.sender);
    }

    /// @param _destinationChainSelector The selector of the destination chain.
    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowed(_destinationChainSelector);
        _;
    }

    /// @param _receiver The receiver address.
    modifier validateReceiver(address _receiver) {
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        _;
    }

    /// @param _sourceChainSelector The selector of the destination chain.
    /// @param _sender address of sender.
    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowed(_sourceChainSelector);
        if (!allowlistedSenders[_sourceChainSelector][_sender]) revert SenderNotAllowed(_sourceChainSelector, _sender);
        _;
    }

    modifier cannotSendZeroTokens(Client.EVMTokenAmount[] memory _tokenAmounts) {
        for (uint256 i = 0; i < _tokenAmounts.length; i++) {
            if (_tokenAmounts[i].amount <= 0) {
                revert CannotSendZeroTokens(_tokenAmounts[i].token);
            }
        }
        _;
    }

    function validateGasFeesAndCalculateExcess(uint256 fees) internal returns (uint256 gasRefundAmount) {
        if (msg.sender != address(this)) {
            // user sends ETH to the router
            if (fees > msg.value) {
                // User sent too little gas, revert.
                revert NotEnoughEthGasFees(msg.value, fees);
            } else if (msg.value > fees) {
                // User sent too much gas, refund the excess.
                gasRefundAmount = msg.value - fees;
            } else {
                gasRefundAmount = 0;
                // User sent just the right amount of gas.
            }
        } else {
            // when contract initiates refund, or transfers withdrawals back to L1
            if (fees > address(this).balance) {
                revert NotEnoughBalance(address(this).balance, fees);
            } else {
                gasRefundAmount = 0;
            }
        }
    }

    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed allowlist status to be set for the destination chain.
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
        emit AllowlistDestinationChain(_destinationChainSelector, allowed);
    }

    /// @param _sourceChainSelector The selector of the source chain to be updated.
    /// @param allowed allowlist status to be set for the source chain.
    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
        emit AllowlistSourceChain(_sourceChainSelector, allowed);
    }

    /// @param _sender address of the sender to be updated.
    /// @param allowed allowlist status to be set for the sender.
    function allowlistSender(uint64 _sourceChainSelector, address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sourceChainSelector][_sender] = allowed;
        emit AllowlistSender(_sourceChainSelector, _sender, allowed);
    }

    /// @notice Sends data and transfer tokens to receiver on the destination chain.
    /// @notice Pay for fees in native gas.
    /// @dev Assumes your contract has sufficient native gas like ETH on Ethereum or MATIC on Polygon.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver address of the recipient on the destination blockchain.
    /// @param _text string data to be sent.
    /// @param _tokenAmounts array of EVMTokenAmount structs (token and amount).
    /// @param _overrideGasLimit set the gaslimit manually. If 0, uses default gasLimits.
    /// @return messageId ID of the CCIP message that was sent.
    function sendMessagePayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        Client.EVMTokenAmount[] memory _tokenAmounts,
        uint256 _overrideGasLimit
    )
        external
        payable
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        validateReceiver(_receiver)
        returns (bytes32 messageId)
    {

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            _text,
            _tokenAmounts,
            address(0), // address(0) means fees are paid in native gas
            _overrideGasLimit
        );

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        uint256 gasRefundAmount = validateGasFeesAndCalculateExcess(fees);

        for (uint256 i = 0; i < _tokenAmounts.length; i++) {
            if (_tokenAmounts[i].amount > 0 && msg.sender != address(this)) {
                // transfer tokens from user to this contract
                IERC20(_tokenAmounts[i].token).safeTransferFrom(
                    msg.sender,
                    address(this),
                    _tokenAmounts[i].amount
                );
            }
            // then approve router to move tokens from this contract
            IERC20(_tokenAmounts[i].token).forceApprove(
                address(router),
                _tokenAmounts[i].amount
            );
        }

        messageId = router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _tokenAmounts,
            address(0),
            fees
        );

        if (gasRefundAmount > 0) {
            (bool success, ) = msg.sender.call{value: gasRefundAmount}("");
            if (!success) {
                revert FailedToRefundExcessEth(msg.sender, gasRefundAmount);
            }
        }

        return messageId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override virtual;

    /// @param _receiver The address of the receiver.
    /// @param _text The string data to be sent.
    /// @param _tokenAmounts array of EVMTokenAmount structs (token and amount).
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @param _overrideGasLimit set the gaslimit manually. If 0, uses default gasLimits.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        Client.EVMTokenAmount[] memory _tokenAmounts,
        address _feeTokenAddress,
        uint256 _overrideGasLimit
    ) internal virtual returns (Client.EVM2AnyMessage memory);

    /// @notice Fallback function to allow the contract to receive Ether.
    receive() external payable {}

    fallback() external payable {}

    /// @notice Allows the contract owner to withdraw Ether from the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    /// @param _amount The amount to withdraw
    function withdraw(address _beneficiary, uint256 _amount) external onlyOwner {
        if (_amount > address(this).balance) revert WithdrawalExceedsBalance(_amount, address(this).balance);
        (bool sent, ) = _beneficiary.call{value: _amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, _amount);
    }

    /// @param _beneficiary address to which the tokens will be sent.
    /// @param _token contract address of the ERC20 token to be withdrawn.
    /// @param _amount The amount to withdraw
    function withdrawToken(
        address _beneficiary,
        address _token,
        uint256 _amount
    ) external virtual onlyOwner {
        uint256 tokenBalance = IERC20(_token).balanceOf(address(this));
        if (_amount > tokenBalance) revert WithdrawalExceedsBalance(_amount, tokenBalance);
        IERC20(_token).safeTransfer(_beneficiary, _amount);
    }

}

