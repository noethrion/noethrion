// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 04 · Propose a new attestation batch on NoethrionAttester (v0.2 quorum).
//
// In the v0.2 m-of-n quorum design, the first validator's call to proposeBatch
// also counts as their first vote. Additional validators (up to threshold) must
// call voteBatch — see 04b_vote_batch.s.sol. With threshold = 1 (the local-dev
// default in Deploy.s.sol), no additional votes are needed.
//
// Reads:
//   $ATTESTER  — deployed NoethrionAttester address on the target RPC
//   $EPOCH     — batch epoch (matches the JSON in batch.json)
//   $ROOT      — bytes32 Merkle root from 03_build_merkle_tree.py output
//   $TOTAL_WH  — total watt-hour sum across all leaves (from batch.json)
//   $PRIVATE_KEY — caller key with VALIDATOR_ROLE on the Attester
//
// Run (against a local Anvil with Deploy.s.sol output addresses + the caller
// granted VALIDATOR_ROLE). This file is the readable reference for the call;
// execute it with `cast send` — the same path tools/run_lifecycle.sh takes.
// (`forge script` cannot compile this file directly: examples/ sits outside
// the Foundry root in contracts/, so its imports do not resolve.)
//   export ATTESTER=0x...                    # printed by Deploy.s.sol
//   export EPOCH=1
//   export ROOT=0x...                        # copy from batch.json
//   export TOTAL_WH=450000000000000000000    # sum of amount_wei in batch.json
//   export PRIVATE_KEY=<one of anvil's printed test keys>
//   cast send "$ATTESTER" "proposeBatch(uint64,bytes32,uint128)" \
//       "$EPOCH" "$ROOT" "$TOTAL_WH" \
//       --private-key "$PRIVATE_KEY" --rpc-url http://localhost:8545

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoethrionAttester} from "../../contracts/src/NoethrionAttester.sol";

contract ProposeBatch is Script {
    function run() external {
        address attesterAddr = vm.envAddress("ATTESTER");
        uint64 epoch = uint64(vm.envUint("EPOCH"));
        bytes32 root = vm.envBytes32("ROOT");
        uint128 totalWh = uint128(vm.envUint("TOTAL_WH"));
        uint256 pk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(pk);
        NoethrionAttester attester = NoethrionAttester(attesterAddr);
        attester.proposeBatch(epoch, root, totalWh);
        vm.stopBroadcast();

        console2.log("Proposed batch (first vote recorded):");
        console2.log("  epoch    :", epoch);
        console2.log("  root     :", vm.toString(root));
        console2.log("  total_wh :", totalWh);
        console2.log("");
        console2.log("Next:");
        console2.log("  - If threshold > 1: run 04b_vote_batch.s.sol from threshold-1 other validators");
        console2.log("  - Wait the challenge window, then run 05_finalize_batch.s.sol");
    }
}
