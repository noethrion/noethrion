// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";

/**
 * @dev Mock token that, on first `mint()`, attempts to re-enter the Attester's
 *      `claim()`. We expect the Attester's `nonReentrant` modifier to block
 *      the inner call. The mock swallows the inner revert so the outer call
 *      can complete and the test can inspect the captured error.
 */
contract MaliciousToken {
    NoethrionAttester public attester;
    bytes public capturedError;
    bool public reentryAttempted;

    uint64 public rEpoch;
    bytes32[] public rProof;
    address public rBeneficiary;
    uint128 public rAmount;

    function setAttester(NoethrionAttester _a) external {
        attester = _a;
    }

    function setReentryParams(uint64 _epoch, bytes32[] memory _proof, address _b, uint128 _amt) external {
        rEpoch = _epoch;
        delete rProof;
        for (uint256 i = 0; i < _proof.length; i++) rProof.push(_proof[i]);
        rBeneficiary = _b;
        rAmount = _amt;
    }

    function mint(address, uint256) external {
        if (reentryAttempted) return; // bound recursion depth
        reentryAttempted = true;
        try attester.claim(rEpoch, rProof, rBeneficiary, rAmount) {
            // Should not reach here — outer call held the nonReentrant lock.
        } catch (bytes memory err) {
            capturedError = err;
        }
    }
}

contract NoethrionAttesterSecurityTest is Test {
    NoethrionAttester internal attester;
    MaliciousToken internal malToken;

    address internal admin = makeAddr("sec-admin");
    address internal validator = makeAddr("sec-validator");
    address internal alice = makeAddr("sec-alice");

    uint256 internal constant CHALLENGE_WINDOW = 1 hours;

    function setUp() public {
        attester = new NoethrionAttester(admin, CHALLENGE_WINDOW, 1);
        malToken = new MaliciousToken();

        bytes32 vRole = attester.VALIDATOR_ROLE();
        vm.startPrank(admin);
        attester.grantRole(vRole, validator);
        attester.setTokenContract(address(malToken));
        vm.stopPrank();
    }

    function test_Reentrancy_BlockedByNonReentrantGuard() public {
        // Single-leaf batch — leaf is the root.
        uint128 amount = 50 ether;
        bytes32 leaf = keccak256(abi.encode(block.chainid, address(attester), alice, amount, uint64(1)));

        vm.prank(validator);
        attester.proposeBatch(1, leaf, amount);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        attester.finalizeBatch(1);

        bytes32[] memory proof = new bytes32[](0);
        malToken.setAttester(attester);
        malToken.setReentryParams(uint64(1), proof, alice, amount);

        // Outer claim — succeeds. Inner re-entry from mint() reverts under the
        // nonReentrant lock, but the mock swallows it so the outer call returns.
        attester.claim(uint64(1), proof, alice, amount);

        assertTrue(malToken.reentryAttempted(), "re-entry not attempted by mock");

        // Captured revert must be ReentrancyGuard's custom error selector.
        bytes memory err = malToken.capturedError();
        assertGt(err.length, 0, "no error captured - re-entry unexpectedly succeeded");
        bytes4 captured = bytes4(err);
        bytes4 expected = bytes4(keccak256("ReentrancyGuardReentrantCall()"));
        assertEq(captured, expected, "captured error is not ReentrancyGuardReentrantCall");

        // Outer mint side-effect did NOT actually mint NOET (mock has no token state),
        // but the contract's claimed flag is set — single, not duplicated.
        assertTrue(attester.claimed(leaf), "outer claim should set the claimed flag");
    }
}
