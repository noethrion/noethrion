// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployProduction} from "../script/DeployProduction.s.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

/**
 * @dev Validates the production role-handoff matrix specified in
 *      ADR-007 (v0.2 interim) and implemented in script/DeployProduction.s.sol.
 *
 *      SINGLE SOURCE OF TRUTH: setUp() calls the script's real
 *      deployAndHandoff() function. It does NOT re-implement the handoff
 *      sequence. A hand-written copy of the sequence is exactly how the
 *      2026-07-27 residual token.ADMIN_ROLE bug passed 31/31 green tests —
 *      the copy reproduced the script's missing renounce verbatim, and the
 *      test then confirmed its own bug as "correct".
 *
 *      INDEPENDENT ORACLE: test_NoDeployAddressRetainsAnyGrantedRole does not
 *      trust any hand-maintained list of role names. It records every
 *      RoleGranted event emitted during the deploy (constructors included),
 *      collects the full set of roles that ever existed, and asserts the
 *      deployer holds none of them on EITHER contract. A role forgotten by
 *      the script cannot also be forgotten by this test.
 *
 *      A regression here means the ADR-007 interim deployment guarantees no
 *      longer hold (the deployer ended with residual privileges, or a role
 *      landed on the wrong holder). Either is critical and should fail loudly
 *      before mainnet.
 */
contract DeployProductionHandoffTest is Test {
    DeployProduction internal deployProd;
    NoethrionAttester internal attester;
    NoethrionToken internal token;
    TimelockController internal timelock;

    address internal deployer;
    uint256 internal deployerPk;
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
        (deployer, deployerPk) = makeAddrAndKey("deploy-prod-deployer");

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

        // Run the REAL script handoff — not a copy of it.
        deployProd = new DeployProduction();
        (attester, token) = deployProd.deployAndHandoff(
            deployerPk, deployer, safe, address(timelock), CHALLENGE_WINDOW, THRESHOLD, validators
        );

        DEFAULT_ADMIN_ROLE_HASH = attester.DEFAULT_ADMIN_ROLE();
        ADMIN_ROLE_HASH = attester.ADMIN_ROLE();
        PAUSER_ROLE_HASH = attester.PAUSER_ROLE();
        VALIDATOR_ROLE_HASH = attester.VALIDATOR_ROLE();
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

    function test_TimelockHoldsTokenAdmin() public view {
        // Token ADMIN_ROLE (gates authorizeMinter/revokeMinter) lands on the
        // Timelock — minter rotation goes through the 24h delay, mirroring
        // the attester model. Fix for the 2026-07-27 residual-role finding.
        assertTrue(token.hasRole(token.ADMIN_ROLE(), address(timelock)));
    }

    function test_SafeDoesNotHoldTokenAdmin() public view {
        // Inverse guard: the Safe must not hold token ADMIN_ROLE at deploy
        // time, or minter rotation would bypass the 24h timelock.
        assertFalse(token.hasRole(token.ADMIN_ROLE(), safe));
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

    // ─── Residual-role sweep — event-derived, no hand-maintained role list ───

    /// @dev Collects the set of every distinct role that appeared in a
    ///      RoleGranted(bytes32,address,address) event within `logs`.
    function _collectGrantedRoles(Vm.Log[] memory logs)
        internal
        pure
        returns (bytes32[] memory roles, uint256 n)
    {
        bytes32 grantedSig = keccak256("RoleGranted(bytes32,address,address)");
        roles = new bytes32[](logs.length);
        for (uint256 i = 0; i < logs.length; i++) {
            // RoleGranted has 3 indexed params => topics.length == 4.
            if (logs[i].topics.length == 4 && logs[i].topics[0] == grantedSig) {
                bytes32 role = logs[i].topics[1];
                bool seen = false;
                for (uint256 k = 0; k < n; k++) {
                    if (roles[k] == role) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) roles[n++] = role;
            }
        }
    }

    /// @dev True if `holder` holds ANY of `roles` on either contract.
    function _holdsAnyRole(
        NoethrionAttester att,
        NoethrionToken tok,
        bytes32[] memory roles,
        uint256 n,
        address holder
    ) internal view returns (bool) {
        for (uint256 i = 0; i < n; i++) {
            if (att.hasRole(roles[i], holder) || tok.hasRole(roles[i], holder)) {
                return true;
            }
        }
        return false;
    }

    function test_NoDeployAddressRetainsAnyGrantedRole() public {
        // Replaces the old test_DeployerHoldsNoRoles, whose hand-enumerated
        // role list simply omitted token.ADMIN_ROLE — the same omission the
        // script had. Here the role universe is derived from the deploy's own
        // RoleGranted events (constructor grants included), so a role the
        // script forgot to renounce cannot be missing from the oracle.
        vm.recordLogs();
        (NoethrionAttester att, NoethrionToken tok) = deployProd.deployAndHandoff(
            deployerPk, deployer, safe, address(timelock), CHALLENGE_WINDOW, THRESHOLD, validators
        );
        (bytes32[] memory roles, uint256 n) = _collectGrantedRoles(vm.getRecordedLogs());

        // Sanity: the sweep must actually have seen grants, or the oracle is
        // broken and would pass vacuously.
        assertGt(n, 0, "sweep saw no RoleGranted events - oracle broken");

        assertFalse(
            _holdsAnyRole(att, tok, roles, n, deployer),
            "deployer retains a role granted during deploy"
        );
    }

    function test_RoleSweep_DetectsPlantedResidualRole() public {
        // Positive (mutational) control for the sweep above: artificially
        // leave the deployer with a role after handoff and prove the sweep
        // machinery catches it. Guards against the oracle rotting into a
        // vacuous pass.
        vm.recordLogs();
        (NoethrionAttester att, NoethrionToken tok) = deployProd.deployAndHandoff(
            deployerPk, deployer, safe, address(timelock), CHALLENGE_WINDOW, THRESHOLD, validators
        );
        (bytes32[] memory roles, uint256 n) = _collectGrantedRoles(vm.getRecordedLogs());

        assertFalse(_holdsAnyRole(att, tok, roles, n, deployer), "clean deploy must start residual-free");

        // Plant the exact residual from the 2026-07-27 finding.
        bytes32 tokenAdminRole = tok.ADMIN_ROLE();
        vm.prank(safe);
        tok.grantRole(tokenAdminRole, deployer);

        assertTrue(
            _holdsAnyRole(att, tok, roles, n, deployer),
            "sweep failed to detect a planted residual role"
        );
    }

    // ─── Exploit regression — 2026-07-27 residual token.ADMIN_ROLE ───────────

    function test_ExploitRegression_DeployerCannotAuthorizeMinterThenMint() public {
        // Reproduces the reported exploit chain: with a residual
        // token.ADMIN_ROLE the deployer could call authorizeMinter(self) and
        // then mint(self, MAX_SUPPLY) — two calls, straight on the token,
        // bypassing the attester entirely (attester.pause() is NO defense
        // here). After a correct handoff every step must revert.
        uint256 maxSupply = token.MAX_SUPPLY();
        uint256 supplyBefore = token.totalSupply();

        // Step 1: authorizeMinter(self) — gated by ADMIN_ROLE, which the
        // deployer must no longer hold.
        vm.prank(deployer);
        vm.expectRevert();
        token.authorizeMinter(deployer);

        // Step 2 (defense in depth): even direct mint must revert — the
        // deployer must not hold MINTER_ROLE either.
        vm.prank(deployer);
        vm.expectRevert();
        token.mint(deployer, maxSupply);

        assertEq(token.balanceOf(deployer), 0, "deployer minted to itself");
        assertEq(token.totalSupply(), supplyBefore, "total supply changed");
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

    function test_Timelock_CanRotateTokenMinterViaTimelockedExecution() public {
        // The Timelock holds token ADMIN_ROLE, so minter rotation
        // (authorizeMinter/revokeMinter) is possible — but only through the
        // scheduled 24h path. This is the managed-rotation property that
        // option (в) preserves versus renouncing the role into the void.
        address newMinter = makeAddr("rotated-minter");
        bytes memory authCalldata =
            abi.encodeWithSelector(NoethrionToken.authorizeMinter.selector, newMinter);

        vm.prank(safe);
        timelock.schedule(address(token), 0, authCalldata, bytes32(0), bytes32(0), TIMELOCK_DELAY);

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        vm.prank(safe);
        timelock.execute(address(token), 0, authCalldata, bytes32(0), bytes32(0));

        assertTrue(token.hasRole(token.MINTER_ROLE(), newMinter));
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
