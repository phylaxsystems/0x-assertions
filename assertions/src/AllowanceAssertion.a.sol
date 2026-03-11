// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

interface IERC20Allowance {
    function allowance(address owner, address spender) external view returns (uint256);
}

interface ISettlerBase {
    struct AllowedSlippage {
        address payable recipient;
        address buyToken;
        uint256 minAmountOut;
    }
}

interface ISettlerTakerSubmitted is ISettlerBase {
    function execute(AllowedSlippage calldata slippage, bytes[] calldata actions, bytes32)
        external
        payable
        returns (bool);

    function executeWithPermit(
        AllowedSlippage calldata slippage,
        bytes[] calldata actions,
        bytes32,
        bytes memory permitData
    ) external payable returns (bool);
}

interface ISettlerMetaTxn is ISettlerBase {
    function executeMetaTxn(
        AllowedSlippage calldata slippage,
        bytes[] calldata actions,
        bytes32,
        address msgSender,
        bytes calldata sig
    ) external returns (bool);
}

interface IBridgeSettlerTakerSubmitted {
    function execute(bytes[] calldata, bytes32) external payable returns (bool);
}

contract AllowanceAssertion is Assertion {
    bytes32 private constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");

    function triggers() external view override {
        registerCallTrigger(this.assertNoAllowanceExploitation.selector);
    }

    function assertNoAllowanceExploitation() external {
        address adopter = ph.getAssertionAdopter();
        PhEvm.Log[] memory logs = ph.getLogs();
        bytes4[4] memory selectors = _settlerSelectors();

        for (uint256 s = 0; s < selectors.length; s++) {
            PhEvm.CallInputs[] memory calls = ph.getCallInputs(adopter, selectors[s]);
            for (uint256 c = 0; c < calls.length; c++) {
                _checkTransferAllowances(logs, calls[c].id, adopter);
            }
        }
    }

    function _settlerSelectors() private pure returns (bytes4[4] memory) {
        return [
            ISettlerTakerSubmitted.execute.selector,
            ISettlerTakerSubmitted.executeWithPermit.selector,
            ISettlerMetaTxn.executeMetaTxn.selector,
            IBridgeSettlerTakerSubmitted.execute.selector
        ];
    }

    function _checkTransferAllowances(PhEvm.Log[] memory logs, uint256 callId, address adopter) private {
        ph.forkPreCall(callId);

        for (uint256 i = 0; i < logs.length; i++) {
            if (_isTransferEvent(logs[i])) {
                _requireZeroAllowance(logs[i], adopter);
            }
        }
    }

    function _isTransferEvent(PhEvm.Log memory log) private pure returns (bool) {
        return log.topics.length >= 3 && log.topics[0] == TRANSFER_SIG;
    }

    function _requireZeroAllowance(PhEvm.Log memory log, address adopter) private view {
        address from = address(uint160(uint256(log.topics[1])));
        (bool success, bytes memory result) = log.emitter.staticcall(
            abi.encodeWithSelector(IERC20Allowance.allowance.selector, from, adopter)
        );
        if (!success || result.length != 32) return;
        uint256 allowance = abi.decode(result, (uint256));
        require(allowance == 0, "Transfer from address with non-zero allowance to adopter");
    }
}
