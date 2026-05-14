// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Production deployment script for NoethrionAttester + NoethrionToken.
//
// Implements the v0.2 interim model from ADR-007:
//   - Safe 3-of-5 multi-sig holds DEFAULT_ADMIN_ROLE + PAUSER_ROLE on both
//     contracts.
//   - OpenZeppelin TimelockController holds the entire ADMIN_ROLE on the
//     Attester (every admin action — slash, setThreshold, setChallengeWindow,
//     setTokenContract — passes through the 24h delay).
//   - All initial validators get VALIDATOR_ROLE directly from the Safe via
//     the DEFAULT_ADMIN_ROLE (no timelock — granting validator role at
//     genesis is a setup step, not an ongoing admin action).
//   - The deployer EOA renounces every role it briefly held during setup.
//     The script asserts that the deployer ends holding zero roles.
//
// This script DOES NOT deploy the Safe or the Timelock. Those are deployed
// out-of-band (via Safe's official UI and a separate OZ TimelockController
// deploy) before this script runs. Their addresses are passed in via env
// vars and validated to be non-zero, distinct, and to contain bytecode.
//
// Required env vars:
//   PRIVATE_KEY        — deployer; will be granted then renounce every role
//   MAINNET_SAFE       — address of the Safe 3-of-5 multi-sig (deployed
//                        out-of-band)
//   MAINNET_TIMELOCK   — address of the OZ TimelockController (deployed
//                        out-of-band, with the Safe configured as proposer
//                        AND executor, minimum delay = 24h)
//   CHALLENGE_WINDOW   — seconds; protocol-spec default 3600 (1 hour)
//   THRESHOLD          — m in m-of-n validator quorum; production minimum is 3
//   VALIDATORS         — comma-separated list of validator addresses (no
//                        spaces). Must contain at least THRESHOLD entries.
//
// Usage:
//
//   export PRIVATE_KEY=0x...
//   export MAINNET_SAFE=0x...
//   export MAINNET_TIMELOCK=0x...
//   export CHALLENGE_WINDOW=3600
//   export THRESHOLD=3
//   export VALIDATORS=0xV1,0xV2,0xV3,0xV4,0xV5
//   forge script contracts/script/DeployProduction.s.sol \
//       --rpc-url "$MAINNET_RPC_URL" --broadcast --verify
//
// On success, the script prints:
//   ATTESTER address  — the production attester contract
//   TOKEN address     — the production token contract
//   ROLE HANDOFF      — verification block confirming every role landed
//                       on the expected holder and the deployer ended bare.
//
// Cross-references:
//   docs/adr/ADR-007-production-admin-multisig.md — design rationale
//   docs/audit/smart-contracts-audit.md           — pre-audit context

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

contract DeployProduction is Script {
    function run() external {
        // ─── 1. Read + validate environment ───────────────────────────────

        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        address safe = vm.envAddress("MAINNET_SAFE");
        address timelock = vm.envAddress("MAINNET_TIMELOCK");
        uint256 challengeWindow = vm.envOr("CHALLENGE_WINDOW", uint256(1 hours));
        uint256 thresholdArg = vm.envOr("THRESHOLD", uint256(3));
        address[] memory validators = vm.envAddress("VALIDATORS", ",");

        require(safe != address(0), "MAINNET_SAFE unset");
        require(timelock != address(0), "MAINNET_TIMELOCK unset");
        require(safe != timelock, "MAINNET_SAFE must differ from MAINNET_TIMELOCK");
        require(safe != deployer, "MAINNET_SAFE must differ from deployer");
        require(timelock != deployer, "MAINNET_TIMELOCK must differ from deployer");
        require(safe.code.length > 0, "MAINNET_SAFE has no bytecode - not deployed?");
        require(timelock.code.length > 0, "MAINNET_TIMELOCK has no bytecode - not deployed?");

        // Pre-flight: confirm the Timelock is wired the way ADR-007 says it
        // should be wired. A Timelock with the wrong proposer/executor/delay
        // looks fine to grantRole() but silently defeats the model.
        TimelockController tlc = TimelockController(payable(timelock));
        require(
            tlc.hasRole(tlc.PROPOSER_ROLE(), safe),
            "Timelock PROPOSER_ROLE not granted to Safe"
        );
        require(
            tlc.hasRole(tlc.EXECUTOR_ROLE(), safe),
            "Timelock EXECUTOR_ROLE not granted to Safe"
        );
        require(
            tlc.getMinDelay() >= 24 hours,
            "Timelock min delay must be >= 24h"
        );

        require(thresholdArg >= 3, "THRESHOLD must be >= 3 for production");
        require(validators.length >= thresholdArg, "VALIDATORS count < THRESHOLD");
        for (uint256 i = 0; i < validators.length; i++) {
            require(validators[i] != address(0), "validator is zero address");
            for (uint256 j = i + 1; j < validators.length; j++) {
                require(validators[i] != validators[j], "duplicate validator");
            }
        }

        console2.log("==== PRODUCTION DEPLOY - ADR-007 interim model ====");
        console2.log("Deployer       :", deployer);
        console2.log("Safe           :", safe);
        console2.log("Timelock       :", timelock);
        console2.log("Challenge win  :", challengeWindow);
        console2.log("Threshold      :", thresholdArg);
        console2.log("Validators     :", validators.length);
        // Print each validator address on its own line so the operator can
        // glance-verify the parsed env var matches the intended set BEFORE
        // any broadcast happens. Catches operator error where a longer
        // VALIDATORS string than intended silently widens the validator set
        // (reviewer L-4 mitigation).
        for (uint256 i = 0; i < validators.length; i++) {
            console2.log("  validator     :", validators[i]);
        }

        // ─── 2. Deploy + wire + handoff ───────────────────────────────────

        (NoethrionAttester attester, NoethrionToken token) = _deployAndHandoff(
            deployerPk, deployer, safe, timelock, challengeWindow, thresholdArg, validators
        );

        // ─── 3. Verify the handoff completed correctly ────────────────────

        _verifyHandoff(attester, token, deployer, safe, timelock, validators);

        console2.log("");
        console2.log("==== DEPLOY COMPLETE ====");
        console2.log("ATTESTER:", address(attester));
        console2.log("TOKEN   :", address(token));
        console2.log("");
        console2.log("==== ROLE HANDOFF VERIFIED ====");
        console2.log("Attester DEFAULT_ADMIN_ROLE: Safe");
        console2.log("Attester ADMIN_ROLE        : Timelock (24h)");
        console2.log("Attester PAUSER_ROLE       : Safe (no delay)");
        console2.log("Token    DEFAULT_ADMIN_ROLE: Safe");
        console2.log("Deployer roles             : NONE");
        console2.log("");
        console2.log("Next: announce the deploy with the Safe address, the");
        console2.log("Timelock address, the validator set, and the Attester +");
        console2.log("Token addresses above. Reference ADR-007 in the announcement.");
    }

    // ─── helpers (extracted to keep run() under the 16-local stack limit) ───

    function _deployAndHandoff(
        uint256 deployerPk,
        address deployer,
        address safe,
        address timelock,
        uint256 challengeWindow,
        uint256 thresholdArg,
        address[] memory validators
    ) internal returns (NoethrionAttester attester, NoethrionToken token) {
        vm.startBroadcast(deployerPk);

        token = new NoethrionToken(deployer);
        attester = new NoethrionAttester(deployer, challengeWindow, thresholdArg);

        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));

        // Grant validator role to each configured validator while the
        // deployer still holds DEFAULT_ADMIN_ROLE.
        bytes32 validatorRole = attester.VALIDATOR_ROLE();
        for (uint256 i = 0; i < validators.length; i++) {
            attester.grantRole(validatorRole, validators[i]);
        }

        // Attester admin handoff per ADR-007 interim:
        //   Safe     -> DEFAULT_ADMIN_ROLE, PAUSER_ROLE
        //   Timelock -> ADMIN_ROLE (entire role; every admin action goes
        //               through the 24h delay).
        bytes32 defaultAdmin = attester.DEFAULT_ADMIN_ROLE();
        bytes32 adminRole = attester.ADMIN_ROLE();
        bytes32 pauserRole = attester.PAUSER_ROLE();
        attester.grantRole(defaultAdmin, safe);
        attester.grantRole(pauserRole, safe);
        attester.grantRole(adminRole, timelock);

        // Token admin handoff:
        //   Safe     -> DEFAULT_ADMIN_ROLE (token has a single admin surface).
        token.grantRole(token.DEFAULT_ADMIN_ROLE(), safe);

        // Deployer renounces every role it briefly held.
        attester.renounceRole(adminRole, deployer);
        attester.renounceRole(pauserRole, deployer);
        attester.renounceRole(defaultAdmin, deployer);
        token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();
    }

    function _verifyHandoff(
        NoethrionAttester attester,
        NoethrionToken token,
        address deployer,
        address safe,
        address timelock,
        address[] memory validators
    ) internal view {
        bytes32 defaultAdmin = attester.DEFAULT_ADMIN_ROLE();
        bytes32 adminRole = attester.ADMIN_ROLE();
        bytes32 pauserRole = attester.PAUSER_ROLE();
        bytes32 validatorRole = attester.VALIDATOR_ROLE();
        bytes32 tokenDefaultAdmin = token.DEFAULT_ADMIN_ROLE();

        require(attester.hasRole(defaultAdmin, safe), "Safe missing DEFAULT_ADMIN");
        require(attester.hasRole(pauserRole, safe), "Safe missing PAUSER");
        require(attester.hasRole(adminRole, timelock), "Timelock missing ADMIN");
        require(token.hasRole(tokenDefaultAdmin, safe), "Safe missing Token DEFAULT_ADMIN");

        require(!attester.hasRole(defaultAdmin, deployer), "deployer still has DEFAULT_ADMIN");
        require(!attester.hasRole(adminRole, deployer), "deployer still has ADMIN");
        require(!attester.hasRole(pauserRole, deployer), "deployer still has PAUSER");
        require(!token.hasRole(tokenDefaultAdmin, deployer), "deployer still has Token DEFAULT_ADMIN");

        // Defensive: the Timelock MUST NOT hold DEFAULT_ADMIN_ROLE — otherwise
        // it could grant itself any other role and short-circuit ADR-007.
        require(!attester.hasRole(defaultAdmin, timelock), "Timelock unexpectedly holds DEFAULT_ADMIN");

        // Defensive: the Safe MUST NOT hold ADMIN_ROLE — otherwise it could
        // bypass the 24h timelock on slash/setThreshold calls.
        require(!attester.hasRole(adminRole, safe), "Safe unexpectedly holds ADMIN");

        // Every configured validator must end with VALIDATOR_ROLE granted.
        // Catches any silent grantRole failure mid-broadcast — though the
        // pre-flight duplicate + zero-address checks already make this a
        // belt-and-suspenders assertion.
        for (uint256 i = 0; i < validators.length; i++) {
            require(
                attester.hasRole(validatorRole, validators[i]),
                "validator missing VALIDATOR_ROLE"
            );
        }
    }
}
