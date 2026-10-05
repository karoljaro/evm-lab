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

describe("List 01 / Task 02.4 - Double voting", () => {
    it("prevents double voting and ignores voting power received after the snapshot", async () => {
        const {
            token,
            dao,
            publicClient,
            accountA,
            accountB,
            accountC,
        } = await networkHelpers.loadFixture(
            deployGovernanceFixture,
        );

        // Account A activates its voting power.
        const delegateAHash = await token.write.delegate(
            [accountA.account.address],
            {
                account: accountA.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: delegateAHash,
        });

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

        const targets: Address[] = [token.address];
        const values: bigint[] = [0n];
        const calldatas: Hex[] = [calldata];

        const descriptionHash = keccak256(
            stringToHex(description),
        );

        const proposalId = await dao.read.hashProposal([
            targets,
            values,
            calldatas,
            descriptionHash,
        ]);

        const proposeHash = await dao.write.propose(
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

        // First vote from Account A succeeds.
        const firstVoteHash = await dao.write.castVote(
            [
                proposalId,
                1, // For
            ],
            {
                account: accountA.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: firstVoteHash,
        });

        assert.equal(
            await dao.read.hasVoted([
                proposalId,
                accountA.account.address,
            ]),
            true,
        );

        // The same account cannot vote again.
        await assert.rejects(async () => {
            await dao.write.castVote(
                [
                    proposalId,
                    0, // Against
                ],
                {
                    account: accountA.account,
                },
            );
        });

        const [
            againstVotesBefore,
            forVotesBefore,
            abstainVotesBefore,
        ] = await dao.read.proposalVotes([
            proposalId,
        ]);

        assert.equal(
            againstVotesBefore,
            0n,
        );

        assert.equal(
            forVotesBefore,
            parseEther("1000000"),
        );

        assert.equal(
            abstainVotesBefore,
            0n,
        );

        // Transfer voting tokens to Account B only AFTER
        // the proposal snapshot has already been taken.
        const transferHash = await token.write.transfer(
            [
                accountB.account.address,
                parseEther("100000"),
            ],
            {
                account: accountA.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: transferHash,
        });

        // Account B delegates the newly received tokens.
        const delegateBHash = await token.write.delegate(
            [accountB.account.address],
            {
                account: accountB.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: delegateBHash,
        });

        // B has voting power NOW...
        assert.equal(
            await token.read.getVotes([
                accountB.account.address,
            ]),
            parseEther("100000"),
        );

        // ...but had none at the proposal snapshot.
        assert.equal(
            await token.read.getPastVotes([
                accountB.account.address,
                snapshot,
            ]),
            0n,
        );

        // B can submit a vote, but its weight for this
        // proposal is zero because voting power is read
        // from the snapshot.
        const voteBHash = await dao.write.castVote(
            [
                proposalId,
                0, // Against
            ],
            {
                account: accountB.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: voteBHash,
        });

        const [
            againstVotesAfter,
            forVotesAfter,
            abstainVotesAfter,
        ] = await dao.read.proposalVotes([
            proposalId,
        ]);

        assert.equal(
            againstVotesAfter,
            0n,
        );

        assert.equal(
            forVotesAfter,
            parseEther("1000000"),
        );

        assert.equal(
            abstainVotesAfter,
            0n,
        );
    });
});