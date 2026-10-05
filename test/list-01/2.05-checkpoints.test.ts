import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
    encodeFunctionData,
    keccak256,
    parseEther,
    stringToHex,
    type Address,
    type Hex,
} from "viem";

import {
    deployGovernanceFixture,
    networkHelpers,
} from "../fixtures/list-01/governance.fixture.js";

describe("List 01 / Task 02.5 - Checkpoints", () => {
    it("uses voting power from the proposal snapshot instead of current voting power", async () => {
        const {
            token,
            dao,
            publicClient,
            accountA,
            accountC,
            accountD,
        } = await networkHelpers.loadFixture(
            deployGovernanceFixture,
        );

        assert.equal(
            await token.read.balanceOf([
                accountD.account.address,
            ]),
            0n,
        );

        assert.equal(
            await token.read.getVotes([
                accountD.account.address,
            ]),
            0n,
        );

        const description =
            "Wyplata 100 tokenow dla Konta 3(C)";

        const calldata = encodeFunctionData({
            abi: token.abi,
            functionName: "transfer",
            args: [
                accountC.account.address,
                parseEther("100"),
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
            await dao.write.propose(
                [
                    targets,
                    values,
                    calldatas,
                    description,
                ],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: proposeHash,
        });

        const snapshot =
            await dao.read.proposalSnapshot([
                proposalId,
            ]);

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

        assert.equal(
            await dao.read.state([proposalId]),
            1,
        );

        // The proposal snapshot has already happened.
        // Only now Account D receives 50,000 GOV.
        const transferHash =
            await token.write.transfer(
                [
                    accountD.account.address,
                    parseEther("50000"),
                ],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: transferHash,
        });

        const delegateHash =
            await token.write.delegate(
                [accountD.account.address],
                {
                    account: accountD.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: delegateHash,
        });

        // Current voting power exists.
        assert.equal(
            await token.read.getVotes([
                accountD.account.address,
            ]),
            parseEther("50000"),
        );

        // But Account D had no voting power
        // at this proposal's snapshot.
        assert.equal(
            await token.read.getPastVotes([
                accountD.account.address,
                snapshot,
            ]),
            0n,
        );

        // D can technically submit a vote...
        const voteHash =
            await dao.write.castVote(
                [
                    proposalId,
                    1, // For
                ],
                {
                    account: accountD.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: voteHash,
        });

        assert.equal(
            await dao.read.hasVoted([
                proposalId,
                accountD.account.address,
            ]),
            true,
        );

        // ...but the vote has weight 0,
        // because Governor uses snapshot voting power.
        const [
            againstVotes,
            forVotes,
            abstainVotes,
        ] = await dao.read.proposalVotes([
            proposalId,
        ]);

        assert.equal(againstVotes, 0n);
        assert.equal(forVotes, 0n);
        assert.equal(abstainVotes, 0n);
    });
});