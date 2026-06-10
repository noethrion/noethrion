// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// 04b · Cast an additional validator vote on a proposed batch.
//
// Required only when the Attester's threshold > 1 (production deployments).
// Skip this step for local-dev deployments with threshold = 1 — the proposer's
// vote in step 04 already satisfies the quorum.
//
// Reads:
//   $ATTESTER    — deployed NoethrionAttester address
//   $EPOCH       — batch epoch (same as 04)
//   $PRIVATE_KEY — caller key with VALIDATOR_ROLE; MUST NOT be the same
//                  validator that already voted for this epoch (proposer
//                  or prior voter) — the contract reverts with AlreadyVoted.
//
// Run once per additional voter until voteCount[epoch] >= threshold
// (via `cast send` — see the note in 04_propose_batch.s.sol on why these
// example scripts are executed with cast rather than `forge script`):
//   export ATTESTER=0x...
//   export EPOCH=1
//   export PRIVATE_KEY=<distinct validator key>
//   cast send "$ATTESTER" "voteBatch(uint64)" "$EPOCH" \
//       --private-key "$PRIVATE_KEY" --rpc-url http://localhost:8545

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoethrionAttester} from "../../contracts/src/NoethrionAttester.sol";

contract VoteBatch is Script {
    function run() external {
        address attesterAddr = vm.envAddress("ATTESTER");
        uint64 epoch = uint64(vm.envUint("EPOCH"));
        uint256 pk = vm.envUint("PRIVATE_KEY");

        NoethrionAttester attester = NoethrionAttester(attesterAddr);
        uint256 votesBefore = attester.voteCount(epoch);

        vm.startBroadcast(pk);
        attester.voteBatch(epoch);
        vm.stopBroadcast();

        uint256 votesAfter = attester.voteCount(epoch);
        uint256 thr = attester.threshold();

        console2.log("Vote recorded:");
        console2.log("  epoch          :", epoch);
        console2.log("  votes before   :", votesBefore);
        console2.log("  votes after    :", votesAfter);
        console2.log("  threshold      :", thr);
        if (votesAfter >= thr) {
            console2.log("  status         : QUORUM REACHED -- proceed to 05_finalize_batch.s.sol once challenge window elapses");
        } else {
            console2.log("  status         : below quorum -- need", thr - votesAfter, "more vote(s)");
        }
    }
}
