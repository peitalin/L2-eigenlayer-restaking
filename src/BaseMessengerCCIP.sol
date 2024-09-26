// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRouterClient} from "@chainlink/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/ccip/applications/CCIPReceiver.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


abstract contract BaseMessengerCCIP is CCIPReceiver, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(uint64 => bool) public allowlistedDestinationChains;
    mapping(uint64 => bool) public allowlistedSourceChains;
    mapping(address => bool) public allowlistedSenders;

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
        address token,
        uint256 tokenAmount,
        address feeToken,
        uint256 fees
    );

    event MessageReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        address token,
        uint256 tokenAmount
    );

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);
    error DestinationChainNotAllowed(uint64 destinationChainSelector);
    error SourceChainNotAllowed(uint64 sourceChainSelector);
    error SenderNotAllowed(address sender);
    error InvalidReceiverAddress();
    error NotEnoughEthGasFees(uint256 setGasFees, uint256 requiredGasFees);

    constructor(address _router) CCIPReceiver(_router) { }

    function __BaseMessengerCCIP_init() internal {
        OwnableUpgradeable.__Ownable_init();
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
        if (!allowlistedSenders[_sender]) revert SenderNotAllowed(_sender);
        _;
    }

    /// @param _destinationChainSelector The selector of the destination chain to be updated.
    /// @param allowed allowlist status to be set for the destination chain.
    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    /// @param _sourceChainSelector The selector of the source chain to be updated.
    /// @param allowed allowlist status to be set for the source chain.
    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    /// @param _sender address of the sender to be updated.
    /// @param allowed allowlist status to be set for the sender.
    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }

    /// @notice Sends data and transfer tokens to receiver on the destination chain.
    /// @notice Pay for fees in native gas.
    /// @dev Assumes your contract has sufficient native gas like ETH on Ethereum or MATIC on Polygon.
    /// @param _destinationChainSelector The identifier (aka selector) for the destination blockchain.
    /// @param _receiver address of the recipient on the destination blockchain.
    /// @param _text string data to be sent.
    /// @param _token token address.
    /// @param _amount token amount.
    /// @param _overrideGasLimit set the gaslimit manually. If 0, uses default gasLimits.
    /// @return messageId ID of the CCIP message that was sent.
    function sendMessagePayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
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
            _token,
            _amount,
            address(0), // address(0) means fees are paid in native gas
            _overrideGasLimit
        );

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (msg.sender != address(this)) {
            // user sends ETH to the router
            if (fees > msg.value)
                revert NotEnoughEthGasFees(msg.value, fees);
        } else {
            // when contract initiates refund, or transfers withdrawals back to L1
            if (fees > address(this).balance)
                revert NotEnoughBalance(address(this).balance, fees);
        }

        // transfer tokens from user to this contract
        if (_amount > 0 && msg.sender != address(this)) {
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        }
        // then approve router to move tokens from this contract
        IERC20(_token).approve(address(router), _amount);

        messageId = router.ccipSend{value: fees}(
            _destinationChainSelector,
            evm2AnyMessage
        );

        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            _token,
            _amount,
            address(0),
            fees
        );

        return messageId;
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override virtual;

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
    ) internal virtual returns (Client.EVM2AnyMessage memory);

    /// @notice Fallback function to allow the contract to receive Ether.
    receive() external payable {}

    fallback() external payable {}

    /// @notice Allows the contract owner to withdraw the entire balance of Ether from the contract.
    /// @param _beneficiary The address to which the Ether should be sent.
    function withdraw(address _beneficiary) external onlyOwner {
        uint256 amount = address(this).balance;
        if (amount == 0) revert NothingToWithdraw();
        (bool sent, ) = _beneficiary.call{value: amount}("");
        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    /// @param _beneficiary address to which the tokens will be sent.
    /// @param _token contract address of the ERC20 token to be withdrawn.
    function withdrawToken(
        address _beneficiary,
        address _token
    ) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount == 0) revert NothingToWithdraw();
        IERC20(_token).safeTransfer(_beneficiary, amount);
    }


}

