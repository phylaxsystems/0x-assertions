// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {CredibleTestWithBacktesting} from "credible-std/CredibleTestWithBacktesting.sol";
import {BacktestingTypes} from "credible-std/utils/BacktestingTypes.sol";
import {AllowanceAssertion} from "../src/AllowanceAssertion.a.sol";

/// @title Single Transaction Backtesting Tests
/// @notice Tests single transaction backtesting with known fixtures
contract BlockRangeBacktestingTest is CredibleTestWithBacktesting {
    address constant settler = 0xC026251dC69F6e3556331b2E14e72Eb4a34Dd55a;

    function testBlockRangeNoFalsePositives() public {
        try vm.envString("RPC_URL") returns (string memory rpcUrl) {
            uint256 endBlock = vm.envUint("END_BLOCK");
            uint256 blockRange = vm.envOr("BLOCK_RANGE", uint256(100));

            BacktestingTypes.BacktestingResults memory results = executeBacktest(
                BacktestingTypes.BacktestingConfig({
                    targetContract: settler,
                    endBlock: endBlock,
                    blockRange: blockRange,
                    assertionCreationCode: type(AllowanceAssertion).creationCode,
                    assertionSelector: AllowanceAssertion.assertNoAllowanceExploitation.selector,
                    rpcUrl: rpcUrl,
                    detailedBlocks: true,
                    forkByTxHash: true
                })
            );

            console.log("Total transactions:", results.totalTransactions);
            console.log("Processed:", results.processedTransactions);
            console.log("Passed:", results.successfulValidations);
            console.log("Failures:", results.assertionFailures);
            assertEq(results.assertionFailures, 0, "Should have no false positives");
        } catch {
            console.log("SKIP: RPC_URL or END_BLOCK not set");
        }
    }
}

contract SingleTxBacktestingTest is CredibleTestWithBacktesting {
    address constant settler = 0xC026251dC69F6e3556331b2E14e72Eb4a34Dd55a;

    /// @notice Test single transaction backtesting with a known transfer
    /// @dev This test requires RPC access to Optimism Sepolia
    function testSingleTransactionBacktest() public {
        // Skip if no RPC available (for CI without RPC secrets)
        try vm.envString("RPC_URL") returns (string memory rpcUrl) {
            bytes32 txHash = vm.envBytes32("TX_HASH");

            if (txHash == bytes32(0)) {
                console.log("SKIP: No fixture transaction hash configured");
                return;
            }

            BacktestingTypes.BacktestingResults memory results = executeBacktestForTransaction(
                txHash,
                settler,
                type(AllowanceAssertion).creationCode,
                AllowanceAssertion.assertNoAllowanceExploitation.selector,
                rpcUrl
            );

            assertEq(results.totalTransactions, 1, "Should process exactly 1 transaction");
            assertGt(results.assertionFailures, 0, "Should detect the exploit");
        } catch {
            console.log("SKIP: RPC_URL not set");
        }
    }
}
