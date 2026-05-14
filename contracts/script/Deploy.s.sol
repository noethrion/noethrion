// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Reference deployment script for a local development environment.
//
// Deploys NoethrionAttester + NoethrionToken, wires them together
// (Attester is granted MINTER_ROLE on Token; Token contract address is
// registered on the Attester), and grants a deployer-configurable
// account the VALIDATOR_ROLE needed to submit batches.
//
// Usage (against a local Anvil node — `anvil` in another terminal):
//
//   # PRIVATE_KEY: any local test key. When Anvil starts it prints ten
//   # pre-funded test accounts and their private keys to stdout — pick
//   # any one. NEVER use this script with a key holding real funds.
//   export PRIVATE_KEY=<one of anvil's printed test keys>
//   export VALIDATOR=<any test address that should submit batches>
//   export CHALLENGE_WINDOW=3600
//   forge script contracts/script/Deploy.s.sol \
//       --rpc-url http://localhost:8545 --broadcast
//
// On success, the script prints:
//   ATTESTER address — paste into examples/lifecycle/04..06 ATTESTER env
//   TOKEN address    — paste into examples/lifecycle/06 TOKEN env
//
// PRIVATE_KEY      — deployer; will receive DEFAULT_ADMIN_ROLE + ADMIN_ROLE
//                    + PAUSER_ROLE on the Attester, and DEFAULT_ADMIN_ROLE
//                    + ADMIN_ROLE on the Token.
// VALIDATOR        — address that gets VALIDATOR_ROLE on the Attester
//                    (i.e., the address allowed to propose / vote on batches).
//                    Defaults to the deployer if not set.
// CHALLENGE_WINDOW — seconds between submission and earliest finalization;
//                    defaults to 1 hour if unset.
// THRESHOLD        — m in m-of-n validator quorum (defaults to 1 for local
//                    dev, which makes single-validator proposeBatch behave
//                    like the old submitBatch). Production deployments set
//                    THRESHOLD >= 3 with at least THRESHOLD distinct
//                    addresses granted VALIDATOR_ROLE.

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {NoethrionAttester} from "../src/NoethrionAttester.sol";
import {NoethrionToken} from "../src/NoethrionToken.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        uint256 challengeWindow = vm.envOr("CHALLENGE_WINDOW", uint256(1 hours));
        uint256 thresholdArg = vm.envOr("THRESHOLD", uint256(1));
        address validator = vm.envOr("VALIDATOR", deployer);

        console2.log("Deployer    :", deployer);
        console2.log("Validator   :", validator);
        console2.log("Challenge window (s):", challengeWindow);
        console2.log("Threshold (m of n)  :", thresholdArg);

        vm.startBroadcast(deployerPk);

        // 1. Deploy Token with the deployer as admin.
        NoethrionToken token = new NoethrionToken(deployer);

        // 2. Deploy Attester with the deployer as admin + the configured
        //    challenge window + threshold.
        NoethrionAttester attester = new NoethrionAttester(deployer, challengeWindow, thresholdArg);

        // 3. Wire the two — Attester points at the Token, Token authorises
        //    the Attester as a minter.
        attester.setTokenContract(address(token));
        token.authorizeMinter(address(attester));

        // 4. Grant the configured validator the VALIDATOR_ROLE so it can
        //    submit batches.
        attester.grantRole(attester.VALIDATOR_ROLE(), validator);

        vm.stopBroadcast();

        console2.log("");
        console2.log("==== DEPLOY COMPLETE ====");
        console2.log("ATTESTER:", address(attester));
        console2.log("TOKEN   :", address(token));
        console2.log("");
        console2.log("Next: export ATTESTER and TOKEN, run examples/lifecycle/04..07");
    }
}
