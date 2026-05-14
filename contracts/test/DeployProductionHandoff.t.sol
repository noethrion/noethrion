// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Validates the production role-handoff matrix specified in
 *      ADR-007 (v0.2 interim) and implemented in script/DeployProduction.s.sol.
 *
 *      The script itself uses vm.envAddress() for the Safe + Timelock
 *      addresses, so we cannot unit-test it directly without setting env
 *      vars. Instead, this test mirrors the script's handoff sequence
 *      step-for-step and asserts the post-state matches the ADR.
 *
 *      A regression here means either the ADR-007 interim deployment guarantees
 *      no longer hold (the deployer ended with residual privileges, or a role
 *      landed on the wrong contract), or the test diverged from the script.
 *      Either is critical and should fail loudly before mainnet.
 */
contract DeployProductionHandoffTest is Test {
    NoethrionAttester internal attester;
    NoethrionToken internal token;
    TimelockController internal timelock;

    address internal deployer = makeAddr("deploy-prod-deployer");
    address internal safe = makeAddr("deploy-prod-safe");

    uint256 internal constant CHALLENGE_WINDOW = 1 hours;
    uint256 internal constant THRESHOLD = 3;
    uint256 internal constant TIMELOCK_DELAY = 24 hours;

    address[] internal validators;

    bytes32 internal DEFAULT_ADMIN_ROLE_HASH;
    bytes32 internal ADMIN_ROLE_HASH;
    bytes32 internal PAUSER_ROLE_HASH;
    bytes32 internal VALIDATOR_ROLE_HASH;

    function setUp() public {
        // Make the Safe mock pass the `code.length > 0` guard in the script.
        vm.etch(safe, hex"60006000");

        // Spin up a real OZ TimelockController. PROPOSER and EXECUTOR
        // permissions go to the Safe (which the script assumes is also
        // already deployed); admin starts as address(0) so the role
        // hierarchy is locked to PROPOSER/EXECUTOR.
        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory executors = new address[](1);
        executors[0] = safe;
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(0));

        // Three validators — the production minimum.
        validators.push(makeAddr("deploy-prod-validator-0"));
        validators.push(makeAddr("deploy-prod-validator-1"));
        validators.push(makeAddr("deploy-prod-validator-2"));

        // Run the script's role-handoff sequence as the deployer.
        vm.startPrank(deployer);

        token = new NoethrionToken(deployer);
        attester = new NoethrionAttester(deployer, CHALLENGE_WINDOW, THRESHOLD);
        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));

        DEFAULT_ADMIN_ROLE_HASH = attester.DEFAULT_ADMIN_ROLE();
        ADMIN_ROLE_HASH = attester.ADMIN_ROLE();
        PAUSER_ROLE_HASH = attester.PAUSER_ROLE();
        VALIDATOR_ROLE_HASH = attester.VALIDATOR_ROLE();

        for (uint256 i = 0; i < validators.length; i++) {
            attester.grantRole(VALIDATOR_ROLE_HASH, validators[i]);
        }

        // Per ADR-007 interim:
        //   Safe        -> DEFAULT_ADMIN_ROLE, PAUSER_ROLE
        //   Timelock    -> ADMIN_ROLE (the entire role; v0.2 contract has a
        //                  single ADMIN_ROLE gating slash, setThreshold,
        //                  setChallengeWindow, setTokenContract).
        attester.grantRole(DEFAULT_ADMIN_ROLE_HASH, safe);
        attester.grantRole(PAUSER_ROLE_HASH, safe);
        attester.grantRole(ADMIN_ROLE_HASH, address(timelock));

        // Token DEFAULT_ADMIN_ROLE moves to the Safe.
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), safe);

        // Deployer renounces every role.
        attester.renounceRole(ADMIN_ROLE_HASH, deployer);
        attester.renounceRole(PAUSER_ROLE_HASH, deployer);
        attester.renounceRole(DEFAULT_ADMIN_ROLE_HASH, deployer);
        token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopPrank();
    }

    // ─── ADR-007 interim post-state ──────────────────────────────────────────

    function test_SafeHoldsAttesterDefaultAdmin() public view {
        assertTrue(attester.hasRole(DEFAULT_ADMIN_ROLE_HASH, safe));
    }

    function test_SafeHoldsAttesterPauser() public view {
        assertTrue(attester.hasRole(PAUSER_ROLE_HASH, safe));
    }

    function test_TimelockHoldsAttesterAdmin() public view {
        assertTrue(attester.hasRole(ADMIN_ROLE_HASH, address(timelock)));
    }

    function test_SafeDoesNotHoldAttesterAdmin() public view {
        // CRITICAL inverse — if the Safe also held ADMIN_ROLE the 24-hour
        // timelock could be bypassed by calling slash/setThreshold directly
        // from the multi-sig, defeating ADR-007.
        assertFalse(attester.hasRole(ADMIN_ROLE_HASH, safe));
    }

    function test_DeployerDoesNotHoldValidatorRole() public view {
        // The deployer is granted validator-management capability via
        // DEFAULT_ADMIN_ROLE during setup, then renounces all roles. The
        // deployer must end with no VALIDATOR_ROLE either, even though they
        // never explicitly grant themselves one.
        assertFalse(attester.hasRole(VALIDATOR_ROLE_HASH, deployer));
    }

    function test_SafeHoldsTokenDefaultAdmin() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), safe));
    }

    function test_DeployerHoldsNoRoles() public view {
        assertFalse(attester.hasRole(DEFAULT_ADMIN_ROLE_HASH, deployer));
        assertFalse(attester.hasRole(ADMIN_ROLE_HASH, deployer));
        assertFalse(attester.hasRole(PAUSER_ROLE_HASH, deployer));
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
    }

    function test_TimelockDoesNotHoldDefaultAdmin() public view {
        // CRITICAL: if the Timelock also held DEFAULT_ADMIN, it could grant
        // itself any other role and short-circuit the ADR-007 model.
        assertFalse(attester.hasRole(DEFAULT_ADMIN_ROLE_HASH, address(timelock)));
    }

    function test_AllValidatorsHaveValidatorRole() public view {
        for (uint256 i = 0; i < validators.length; i++) {
            assertTrue(attester.hasRole(VALIDATOR_ROLE_HASH, validators[i]));
        }
    }

    // ─── Operational checks — what each role can and cannot do ───────────────

    function test_Timelock_CanCallSlashViaTimelockedExecution() public {
        // The Timelock can call slash because it holds ADMIN_ROLE.
        // The Safe (PROPOSER) schedules + the Safe (EXECUTOR) executes after the
        // 24h delay; here we simulate by warping time and calling execute().
        address victim = validators[0];
        bytes32 evidence = keccak256("test-evidence");

        bytes memory slashCalldata =
            abi.encodeWithSelector(NoethrionAttester.slash.selector, victim, evidence);

        bytes32 salt = bytes32(0);
        bytes32 predecessor = bytes32(0);

        vm.prank(safe);
        timelock.schedule(
            address(attester), 0, slashCalldata, predecessor, salt, TIMELOCK_DELAY
        );

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        vm.prank(safe);
        timelock.execute(address(attester), 0, slashCalldata, predecessor, salt);

        assertFalse(attester.hasRole(VALIDATOR_ROLE_HASH, victim));
        assertEq(attester.slashEvidence(victim), evidence);
    }

    function test_Safe_CanPauseWithoutTimelock() public {
        // PAUSER_ROLE on the Safe allows immediate pause — no timelock.
        // Critical for incident response.
        assertFalse(attester.paused());

        vm.prank(safe);
        attester.pause();

        assertTrue(attester.paused());
    }

    function test_Deployer_CannotPauseAfterHandoff() public {
        vm.prank(deployer);
        vm.expectRevert();
        attester.pause();
    }

    function test_Deployer_CannotSlashAfterHandoff() public {
        vm.prank(deployer);
        vm.expectRevert();
        attester.slash(validators[0], keccak256("x"));
    }

    function test_Deployer_CannotGrantValidatorRoleAfterHandoff() public {
        // DEFAULT_ADMIN_ROLE manages other roles. After the deployer renounces
        // it, they cannot grant or revoke anything.
        address randomAddr = makeAddr("random");
        vm.prank(deployer);
        vm.expectRevert();
        attester.grantRole(VALIDATOR_ROLE_HASH, randomAddr);
    }

    function test_Safe_CanGrantValidatorRoleAfterHandoff() public {
        // The Safe (DEFAULT_ADMIN) retains the power to add new validators
        // — needed for ongoing validator-set maintenance.
        address newValidator = makeAddr("post-handoff-validator");
        vm.prank(safe);
        attester.grantRole(VALIDATOR_ROLE_HASH, newValidator);
        assertTrue(attester.hasRole(VALIDATOR_ROLE_HASH, newValidator));
    }

    function test_Timelock_CannotPauseDirectly() public {
        // PAUSER_ROLE is on the Safe, not the Timelock. The Timelock can
        // only do what ADMIN_ROLE permits (slash, setThreshold, etc.).
        vm.prank(address(timelock));
        vm.expectRevert();
        attester.pause();
    }
}
