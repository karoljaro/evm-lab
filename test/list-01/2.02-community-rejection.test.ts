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

describe("List 01 / Task 02.2 - Community rejection", () => {
    it("rejects a proposal when Against votes outweigh For votes", async () => {
        const {
            token,
            dao,
            publicClient,
            accountA,
            accountB,
            accountC,
        } = await networkHelpers.loadFixture(deployGovernanceFixture);

        // Account A starts with 1,000,000 GOV.
        // Transfer 400,000 GOV to Account B.
        const transferHash = await token.write.transfer(
            [
                accountB.account.address,
                parseEther("400000"),
            ],
            {
                account: accountA.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: transferHash,
        });

        const delegateAHash = await token.write.delegate(
            [accountA.account.address],
            {
                account: accountA.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: delegateAHash,
        });

        const delegateBHash = await token.write.delegate(
            [accountB.account.address],
            {
                account: accountB.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: delegateBHash,
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
            await dao.read.proposalSnapshot([proposalId]);

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

        // Account A: 600,000 GOV -> Against
        const voteAHash = await dao.write.castVote(
            [
                proposalId,
                0,
            ],
            {
                account: accountA.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: voteAHash,
        });

        // Account B: 400,000 GOV -> For
        const voteBHash = await dao.write.castVote(
            [
                proposalId,
                1,
            ],
            {
                account: accountB.account,
            },
        );

        await publicClient.waitForTransactionReceipt({
            hash: voteBHash,
        });

        const [
            againstVotes,
            forVotes,
            abstainVotes,
        ] = await dao.read.proposalVotes([
            proposalId,
        ]);

        assert.equal(
            againstVotes,
            parseEther("600000"),
        );

        assert.equal(
            forVotes,
            parseEther("400000"),
        );

        assert.equal(
            abstainVotes,
            0n,
        );

        // Finish voting.
        const deadline =
            await dao.read.proposalDeadline([proposalId]);

        currentBlock =
            await publicClient.getBlockNumber();

        const blocksUntilDeadline =
            deadline >= currentBlock
                ? deadline - currentBlock + 1n
                : 0n;

        if (blocksUntilDeadline > 0n) {
            await networkHelpers.mine(
                Number(blocksUntilDeadline),
            );
        }

        // 3 = Defeated
        assert.equal(
            await dao.read.state([proposalId]),
            3,
        );

        // A defeated proposal cannot be executed.
        await assert.rejects(
            async () => {
                await dao.write.execute(
                    [
                        targets,
                        values,
                        calldatas,
                        descriptionHash,
                    ],
                    {
                        account: accountA.account,
                    },
                );
            },
        );
    });
});