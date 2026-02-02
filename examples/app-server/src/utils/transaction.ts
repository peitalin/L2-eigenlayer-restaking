import { decodeEventLog, parseAbi, PublicClient } from "viem";
import {
  BRIDGING_REWARDS_TO_L2_SIGNATURE,
  BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE,
  MESSAGE_SENT_SIGNATURE
} from "./constants";
import { ErrorResponse } from "../types";
import { fetchCCIPMessageData } from "./ccip";
import { CCIPTransaction } from "../server";
import * as db from "../db";
import logger from './logger';

// Helper function to convert numeric state to string status
export function getStatusFromState(state: number, data: any): string {
  switch (state) {
    case 0:
      return 'INFLIGHT';
    case 1:
      return 'PENDING';
    case 2:
      return 'SUCCESS';
    case 3:
      return 'FAILED';
    default:
      // If we can't determine state, check if there's a receipt
      if (data.receiptTransactionHash) {
        return 'SUCCESS';
      }
      if (data.blessBlockNumber) {
        return 'BLESSED';
      }
      return 'PENDING';
  }
}

/**
 * Extract a CCIP messageId and agentOwner from a transaction receipt
 * @param txHash Transaction hash to extract data from
 * @param client Viem public client to use for fetching the receipt
 * @returns Object containing messageId and agentOwner if found
 */
export const extractMessageIdFromTxHash = async (
  txHash: string,
  client: PublicClient,
  retryCount = 0
): Promise<{ messageId: string | null, agentOwner: string | null }> => {
  if (!txHash || !txHash.startsWith('0x')) {
    logger.error('Invalid tx hash provided:', txHash);
    return { messageId: null, agentOwner: null };
  }

  try {
    logger.info(`Getting transaction receipt for: ${txHash}`);
    const hash = txHash as `0x${string}`;

    try {
      const receipt = await client.getTransactionReceipt({
        hash
      });

      logger.info(`Receipt contains ${receipt.logs.length} logs`);

      // Initialize return values
      let foundMessageId: string | null = null;
      let foundAgentOwner: string | null = null;

      // Find logs that contain the events we're interested in
      for (const log of receipt.logs) {
        // Check for MessageSent event
        if (log.topics[0] === MESSAGE_SENT_SIGNATURE) {
          try {
            logger.info('Found MessageSent event, decoding...');
            const decodedLog = decodeEventLog({
              abi: parseAbi(['event MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)']),
              data: log.data,
              topics: log.topics
            });

            if (decodedLog && decodedLog.args) {
              foundMessageId = decodedLog.args[0];
              logger.info(`Extracted messageId: ${foundMessageId}`);
            }
          } catch (decodeError) {
            logger.error('Error decoding MessageSent event:', decodeError);
            // Fallback extraction for messageId
            if (log.topics.length > 1) {
              const topic = log.topics[1];
              if (topic) {
                foundMessageId = topic;
                logger.info(`Extracted messageId using fallback method: ${foundMessageId}`);
              }
            }
          }
        }

        // Check for BridgingWithdrawalToL2 event
        else if (log.topics[0] === BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE) {
          try {
            logger.info('Found BridgingWithdrawalToL2 event, decoding...');
            const decodedLog = decodeEventLog({
              abi: parseAbi(['event BridgingWithdrawalToL2(address indexed agentOwner, (address, uint256)[] withdrawalTokenAmounts)']),
              data: log.data,
              topics: log.topics
            });

            if (decodedLog && decodedLog.args) {
              const args = decodedLog.args as any;
              if (args.agentOwner) {
                foundAgentOwner = args.agentOwner.toLowerCase();
                logger.info(`Extracted agentOwner from BridgingWithdrawalToL2: ${foundAgentOwner}`);
              }
            }
          } catch (decodeError) {
            logger.error('Error decoding BridgingWithdrawalToL2 event:', decodeError);
            // Fallback extraction for agentOwner
            if (log.topics.length > 1) {
              const topic = log.topics[1];
              if (topic) {
                const address = `0x${topic.slice(26).toLowerCase()}`;
                // Validate that we have a proper address
                if (address.length === 42) {
                  foundAgentOwner = address;
                  logger.info(`Extracted agentOwner using fallback method: ${foundAgentOwner}`);
                }
              }
            }
          }
        }

        // Check for BridgingRewardsToL2 event
        else if (log.topics[0] === BRIDGING_REWARDS_TO_L2_SIGNATURE) {
          try {
            logger.info('Found BridgingRewardsToL2 event, decoding...');
            const decodedLog = decodeEventLog({
              abi: parseAbi(['event BridgingRewardsToL2(address indexed agentOwner, (address, uint256)[] rewardsTokenAmounts)']),
              data: log.data,
              topics: log.topics
            });

            if (decodedLog && decodedLog.args) {
              const args = decodedLog.args as any;
              if (args.agentOwner) {
                foundAgentOwner = args.agentOwner.toLowerCase();
                logger.info(`Extracted agentOwner from BridgingRewardsToL2: ${foundAgentOwner}`);
              }
            }
          } catch (decodeError) {
            logger.error('Error decoding BridgingRewardsToL2 event:', decodeError);
            // Fallback extraction for agentOwner
            if (log.topics.length > 1) {
              const topic = log.topics[1];
              if (topic) {
                const address = `0x${topic.slice(26).toLowerCase()}`;
                // Validate that we have a proper address
                if (address.length === 42) {
                  foundAgentOwner = address;
                  logger.info(`Extracted agentOwner using fallback method: ${foundAgentOwner}`);
                }
              }
            }
          }
        }
      }

      return { messageId: foundMessageId, agentOwner: foundAgentOwner };
    } catch (error) {
      const errorResponse = error as ErrorResponse;
      // Check if this is a TransactionReceiptNotFoundError (transaction not mined yet)
      if (errorResponse.shortMessage && errorResponse.shortMessage.includes('could not be found') && retryCount < 3) {
        // Transaction not mined yet, retry with exponential backoff if within retry limit
        const delayMs = Math.pow(2, retryCount) * 1000; // Exponential backoff: 1s, 2s, 4s
        logger.info(`Transaction ${txHash} not mined yet. Retrying in ${delayMs/1000} seconds... (attempt ${retryCount + 1}/3)`);

        // Wait and retry
        await new Promise(resolve => setTimeout(resolve, delayMs));
        return extractMessageIdFromTxHash(txHash, client, retryCount + 1);
      }

      logger.error(`Error processing transaction receipt for ${txHash}:`, error);
      return { messageId: null, agentOwner: null };
    }
  } catch (outerError) {
    logger.error(`Unexpected error processing transaction receipt for ${txHash}:`, outerError);
    return { messageId: null, agentOwner: null };
  }
};


// Function to update a transaction's status by checking its CCIP message
export async function updateTransactionStatus(messageId: string): Promise<void> {
  try {
    // Get the transaction by messageId
    const transaction = db.getTransactionByMessageId(messageId);
    if (!transaction) {
      logger.info(`No transaction found with messageId ${messageId}`);
      return;
    }

    // Skip if transaction is already complete
    if (transaction.isComplete) {
      logger.info(`Transaction ${transaction.txHash} is already complete`);
      return;
    }

    // Fetch the CCIP message data
    const messageData = await fetchCCIPMessageData(messageId);
    if (!messageData) {
      logger.info(`No CCIP message data found for messageId ${messageId}`);
      return;
    }

    // Update transaction based on message status
    let updates: Partial<CCIPTransaction> = {};

    if (messageData.status === 'SUCCESS') {
      updates = {
        status: 'confirmed',
        isComplete: true,
        receiptTransactionHash: messageData.receiptTransactionHash || transaction.receiptTransactionHash
      };
      logger.info(`Updating transaction ${transaction.txHash} to confirmed status`);
    } else if (messageData.status === 'FAILED') {
      updates = {
        status: 'failed',
        isComplete: true
      };
      logger.info(`Updating transaction ${transaction.txHash} to failed status`);
    } else {
      // Transaction is still in progress, no updates needed
      logger.info(`Transaction ${transaction.txHash} is still in progress (${messageData.status})`);
      return;
    }

    // Apply the updates
    db.updateTransactionByMessageId(messageId, updates);
  } catch (error) {
    logger.error(`Error updating transaction status for messageId ${messageId}:`, error);
    throw error;
  }
}