import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
    encodeFunctionData,
    keccak256,
    stringToHex,
    type Address,
    type Hex,
} from "viem";

import {
    deployShortVotingGovernanceFixture,
    networkHelpers,
} from "../fixtures/list-01/governance.fixture.js";

describe("List 01 / Task 02.3 - Governor settings", () => {
    it("finishes voting after a voting period of 5 blocks", async () => {
        const {
            token,
            dao,
            publicClient,
            accountC,
        } = await networkHelpers.loadFixture(
            deployShortVotingGovernanceFixture,
        );

        // GovernorSettings was deployed with votingPeriod = 5.
        assert.equal(
            await dao.read.votingPeriod(),
            5n,
        );

        const description =
            "Wyplata 100 tokenow dla Konta 3(C)";

        const calldata = encodeFunctionData({
            abi: token.abi,
            functionName: "transfer",
            args: [
                accountC.account.address,
                100n,
            ],
        });

        const targets: Address[] = [
            token.address,
        ];

        const values: bigint[] = [
            0n,
        ];

        const calldatas: Hex[] = [
            calldata,
        ];

        const descriptionHash = keccak256(
            stringToHex(description),
        );

        const proposalId =
            await dao.read.hashProposal([
                targets,
                values,
                calldatas,
                descriptionHash,
            ]);

        const proposeHash =
            await dao.write.propose([
                targets,
                values,
                calldatas,
                description,
            ]);

        await publicClient.waitForTransactionReceipt({
            hash: proposeHash,
        });

        const snapshot =
            await dao.read.proposalSnapshot([
                proposalId,
            ]);

        const deadline =
            await dao.read.proposalDeadline([
                proposalId,
            ]);

        // Governor should have exactly a 5-block voting window.
        assert.equal(
            deadline - snapshot,
            5n,
        );

        let currentBlock =
            await publicClient.getBlockNumber();

        const blocksUntilActive =
            snapshot >= currentBlock
                ? snapshot - currentBlock + 1n
                : 0n;

        if (blocksUntilActive > 0n) {
            await networkHelpers.mine(
                Number(blocksUntilActive),
            );
        }

        // Proposal is now Active.
        assert.equal(
            await dao.read.state([proposalId]),
            1,
        );

        currentBlock =
            await publicClient.getBlockNumber();

        const blocksUntilFinished =
            deadline >= currentBlock
                ? deadline - currentBlock + 1n
                : 0n;

        // After entering Active, exactly 5 more blocks
        // close this voting period.
        assert.equal(
            blocksUntilFinished,
            5n,
        );

        await networkHelpers.mine(
            Number(blocksUntilFinished),
        );

        // Nobody voted, so the proposal is Defeated.
        assert.equal(
            await dao.read.state([proposalId]),
            3,
        );
    });
});