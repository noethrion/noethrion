// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @dev Pre-flight validation logic mirrored from DeployProduction.s.sol.
 *      The script reads its inputs from env vars and calls vm.envAddress(),
 *      which is not directly testable. This contract extracts the pure
 *      validation checks into a function we can fuzz and exercise with
 *      adversarial inputs.
 *
 *      Stays in lock-step with the production deploy script — if a require()
 *      in the script changes, the equivalent check here must change too. A
 *      mismatch is its own bug.
 */
contract DeployValidator {
    error SafeIsZero();
    error TimelockIsZero();
    error SafeEqualsTimelock();
    error SafeEqualsDeployer();
    error TimelockEqualsDeployer();
    error SafeHasNoBytecode();
    error TimelockHasNoBytecode();
    error TimelockProposerMismatch();
    error TimelockExecutorMismatch();
    error TimelockDelayTooShort();
    error ThresholdBelowProduction();
    error ValidatorIsZero();
    error DuplicateValidator();
    error ValidatorsBelowThreshold();

    function validate(
        address deployer,
        address safe,
        address timelock,
        uint256 thresholdArg,
        address[] memory validators
    ) external view {
        if (safe == address(0)) revert SafeIsZero();
        if (timelock == address(0)) revert TimelockIsZero();
        if (safe == timelock) revert SafeEqualsTimelock();
        if (safe == deployer) revert SafeEqualsDeployer();
        if (timelock == deployer) revert TimelockEqualsDeployer();
        if (safe.code.length == 0) revert SafeHasNoBytecode();
        if (timelock.code.length == 0) revert TimelockHasNoBytecode();

        TimelockController tlc = TimelockController(payable(timelock));
        if (!tlc.hasRole(tlc.PROPOSER_ROLE(), safe)) revert TimelockProposerMismatch();
        if (!tlc.hasRole(tlc.EXECUTOR_ROLE(), safe)) revert TimelockExecutorMismatch();
        if (tlc.getMinDelay() < 24 hours) revert TimelockDelayTooShort();

        if (thresholdArg < 3) revert ThresholdBelowProduction();
        if (validators.length < thresholdArg) revert ValidatorsBelowThreshold();
        for (uint256 i = 0; i < validators.length; i++) {
            if (validators[i] == address(0)) revert ValidatorIsZero();
            for (uint256 j = i + 1; j < validators.length; j++) {
                if (validators[i] == validators[j]) revert DuplicateValidator();
            }
        }
    }
}

contract DeployProductionValidationTest is Test {
    DeployValidator internal v;
    address internal deployer = makeAddr("deployer");
    address internal safe = makeAddr("safe");
    TimelockController internal timelock;
    address[] internal validators;

    function setUp() public {
        v = new DeployValidator();
        vm.etch(safe, hex"60006000");

        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory executors = new address[](1);
        executors[0] = safe;
        timelock = new TimelockController(24 hours, proposers, executors, address(0));

        validators.push(makeAddr("v0"));
        validators.push(makeAddr("v1"));
        validators.push(makeAddr("v2"));
    }

    function test_AcceptsValidConfig() public view {
        v.validate(deployer, safe, address(timelock), 3, validators);
    }

    function test_RevertsOnZeroSafe() public {
        vm.expectRevert(DeployValidator.SafeIsZero.selector);
        v.validate(deployer, address(0), address(timelock), 3, validators);
    }

    function test_RevertsOnZeroTimelock() public {
        vm.expectRevert(DeployValidator.TimelockIsZero.selector);
        v.validate(deployer, safe, address(0), 3, validators);
    }

    function test_RevertsOnSafeEqualsTimelock() public {
        // A Safe-as-Timelock collapse would let the multi-sig grant itself
        // ADMIN_ROLE bypassing the delay; this is the M-4 finding.
        vm.expectRevert(DeployValidator.SafeEqualsTimelock.selector);
        v.validate(deployer, safe, safe, 3, validators);
    }

    function test_RevertsOnSafeEqualsDeployer() public {
        vm.expectRevert(DeployValidator.SafeEqualsDeployer.selector);
        v.validate(deployer, deployer, address(timelock), 3, validators);
    }

    function test_RevertsOnTimelockEqualsDeployer() public {
        vm.expectRevert(DeployValidator.TimelockEqualsDeployer.selector);
        v.validate(deployer, safe, deployer, 3, validators);
    }

    function test_RevertsOnSafeWithoutBytecode() public {
        address emptySafe = makeAddr("empty-safe");
        vm.expectRevert(DeployValidator.SafeHasNoBytecode.selector);
        v.validate(deployer, emptySafe, address(timelock), 3, validators);
    }

    function test_RevertsOnTimelockWithoutBytecode() public {
        address emptyTimelock = makeAddr("empty-timelock");
        vm.expectRevert(DeployValidator.TimelockHasNoBytecode.selector);
        v.validate(deployer, safe, emptyTimelock, 3, validators);
    }

    function test_RevertsWhenTimelockProposerIsNotSafe() public {
        address[] memory wrongProposers = new address[](1);
        wrongProposers[0] = makeAddr("wrong-proposer");
        address[] memory executors = new address[](1);
        executors[0] = safe;
        TimelockController bad = new TimelockController(24 hours, wrongProposers, executors, address(0));
        vm.expectRevert(DeployValidator.TimelockProposerMismatch.selector);
        v.validate(deployer, safe, address(bad), 3, validators);
    }

    function test_RevertsWhenTimelockExecutorIsNotSafe() public {
        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory wrongExecutors = new address[](1);
        wrongExecutors[0] = makeAddr("wrong-executor");
        TimelockController bad = new TimelockController(24 hours, proposers, wrongExecutors, address(0));
        vm.expectRevert(DeployValidator.TimelockExecutorMismatch.selector);
        v.validate(deployer, safe, address(bad), 3, validators);
    }

    function test_RevertsOnTimelockDelayBelow24h() public {
        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory executors = new address[](1);
        executors[0] = safe;
        TimelockController short_ = new TimelockController(1 hours, proposers, executors, address(0));
        vm.expectRevert(DeployValidator.TimelockDelayTooShort.selector);
        v.validate(deployer, safe, address(short_), 3, validators);
    }

    function test_RevertsOnThresholdBelowProduction() public {
        vm.expectRevert(DeployValidator.ThresholdBelowProduction.selector);
        v.validate(deployer, safe, address(timelock), 2, validators);
    }

    function test_RevertsOnValidatorsBelowThreshold() public {
        address[] memory tooFew = new address[](2);
        tooFew[0] = makeAddr("v0");
        tooFew[1] = makeAddr("v1");
        vm.expectRevert(DeployValidator.ValidatorsBelowThreshold.selector);
        v.validate(deployer, safe, address(timelock), 3, tooFew);
    }

    function test_RevertsOnZeroValidator() public {
        address[] memory withZero = new address[](3);
        withZero[0] = makeAddr("v0");
        withZero[1] = address(0);
        withZero[2] = makeAddr("v2");
        vm.expectRevert(DeployValidator.ValidatorIsZero.selector);
        v.validate(deployer, safe, address(timelock), 3, withZero);
    }

    function test_RevertsOnDuplicateValidator() public {
        address[] memory dup = new address[](3);
        dup[0] = makeAddr("v0");
        dup[1] = makeAddr("v1");
        dup[2] = makeAddr("v0"); // duplicate
        vm.expectRevert(DeployValidator.DuplicateValidator.selector);
        v.validate(deployer, safe, address(timelock), 3, dup);
    }
}
