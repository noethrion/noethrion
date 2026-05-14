// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Deploy an OpenZeppelin TimelockController configured per ADR-007:
//
//   - Minimum delay: 24 hours (the ADR's binding floor).
//   - PROPOSER_ROLE   = the Safe multi-sig (only the Safe can schedule).
//   - EXECUTOR_ROLE   = the Safe multi-sig (only the Safe can execute
//     once the timelock matures; we deliberately do NOT grant
//     EXECUTOR_ROLE to address(0) — open execution would let any account
//     finalize a mature timelocked call, which is fine for governance but
//     defeats the public-warning property in our context).
//   - admin parameter = address(0). The Timelock then self-administers
//     its own roles via TIMELOCK_ADMIN_ROLE held by the contract itself,
//     so role-management actions also pass through the 24h delay.
//
// Run AFTER the Safe is deployed and BEFORE DeployProduction.s.sol. The
// Safe and Timelock addresses are then fed into DeployProduction via
// MAINNET_SAFE + MAINNET_TIMELOCK env vars.
//
// Required env vars:
//   PRIVATE_KEY   — deployer; receives no roles, just pays gas
//   MAINNET_SAFE  — address of the pre-deployed Safe multi-sig
//   MIN_DELAY     — seconds; default 86400 (24h). MUST be >= 86400 for
//                   ADR-007 compliance — DeployProduction.s.sol enforces.
//
// Usage:
//
//   export PRIVATE_KEY=0x...
//   export MAINNET_SAFE=0x...
//   export MIN_DELAY=86400
//   forge script contracts/script/DeployTimelock.s.sol \
//       --rpc-url "$MAINNET_RPC_URL" --broadcast --verify
//
// Cross-references:
//   docs/adr/ADR-007-production-admin-multisig.md
//   docs/runbooks/production-deploy.md

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployTimelock is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        address safe = vm.envAddress("MAINNET_SAFE");
        uint256 minDelay = vm.envOr("MIN_DELAY", uint256(86400)); // 24h default

        require(safe != address(0), "MAINNET_SAFE unset");
        require(safe.code.length > 0, "MAINNET_SAFE has no bytecode - not deployed?");
        require(safe != deployer, "MAINNET_SAFE must differ from deployer");
        require(minDelay >= 86400, "MIN_DELAY must be >= 24h per ADR-007");

        console2.log("==== DEPLOY TIMELOCK CONTROLLER ====");
        console2.log("Deployer    :", deployer);
        console2.log("Safe        :", safe);
        console2.log("Min delay   :", minDelay, "seconds");

        // PROPOSER and EXECUTOR are both the Safe — the multi-sig schedules
        // and the same multi-sig executes once the delay elapses. We do NOT
        // pass address(0) as EXECUTOR (which would open execution to anyone)
        // because the public-warning property of the timelock relies on the
        // execute step also being multi-sig-gated.
        address[] memory proposers = new address[](1);
        proposers[0] = safe;
        address[] memory executors = new address[](1);
        executors[0] = safe;

        vm.startBroadcast(deployerPk);
        TimelockController timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            address(0) // admin = address(0) -> Timelock self-administers
        );
        vm.stopBroadcast();

        // Verify the deployed state matches what DeployProduction.s.sol
        // expects. If any of these fail, the deploy is wrong and the
        // production deploy script will refuse to broadcast on top of it.
        require(
            timelock.hasRole(timelock.PROPOSER_ROLE(), safe),
            "Safe missing PROPOSER_ROLE"
        );
        require(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), safe),
            "Safe missing EXECUTOR_ROLE"
        );
        require(timelock.getMinDelay() == minDelay, "min delay mismatch");
        // The Timelock should NOT have an external admin — it should
        // administer itself via TIMELOCK_ADMIN_ROLE granted to the contract
        // address in the constructor when admin == address(0).
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        require(
            !timelock.hasRole(adminRole, deployer),
            "deployer unexpectedly holds Timelock DEFAULT_ADMIN_ROLE"
        );
        require(
            !timelock.hasRole(adminRole, safe),
            "Safe unexpectedly holds Timelock DEFAULT_ADMIN_ROLE"
        );

        console2.log("");
        console2.log("==== TIMELOCK DEPLOY COMPLETE ====");
        console2.log("TIMELOCK ADDRESS:", address(timelock));
        console2.log("");
        console2.log("Next:");
        console2.log("  1. Verify on the explorer that the Safe holds both");
        console2.log("     PROPOSER_ROLE and EXECUTOR_ROLE on this Timelock.");
        console2.log("  2. Verify that no EOA (including the deployer) holds");
        console2.log("     DEFAULT_ADMIN_ROLE on this Timelock.");
        console2.log("  3. Export MAINNET_TIMELOCK to the address above and");
        console2.log("     run contracts/script/DeployProduction.s.sol.");
    }
}
