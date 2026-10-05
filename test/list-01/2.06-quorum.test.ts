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

describe("List 01 / Task 02.6 - Abstain and quorum", () => {
    it("counts Abstain votes toward quorum without counting them as Against", async () => {
        const {
            token,
            dao,
            publicClient,
            accountA,
            accountB,
            accountC,
            accountD,
        } = await networkHelpers.loadFixture(
            deployGovernanceFixture,
        );

        // Account A initially owns 1,000,000 GOV.
        //
        // Give Account B 50,000 GOV and move the remaining
        // excess from A to D so that A also has exactly 50,000 GOV.
        const transferToBHash =
            await token.write.transfer(
                [
                    accountB.account.address,
                    parseEther("50000"),
                ],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: transferToBHash,
        });

        const transferToDHash =
            await token.write.transfer(
                [
                    accountD.account.address,
                    parseEther("900000"),
                ],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: transferToDHash,
        });

        assert.equal(
            await token.read.balanceOf([
                accountA.account.address,
            ]),
            parseEther("50000"),
        );

        assert.equal(
            await token.read.balanceOf([
                accountB.account.address,
            ]),
            parseEther("50000"),
        );

        // Activate voting power before the proposal snapshot.
        const delegateAHash =
            await token.write.delegate(
                [accountA.account.address],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: delegateAHash,
        });

        const delegateBHash =
            await token.write.delegate(
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

        // Account A -> Abstain
        const abstainVoteHash =
            await dao.write.castVote(
                [
                    proposalId,
                    2,
                ],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: abstainVoteHash,
        });

        // Account B -> For
        const forVoteHash =
            await dao.write.castVote(
                [
                    proposalId,
                    1,
                ],
                {
                    account: accountB.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: forVoteHash,
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
            0n,
        );

        assert.equal(
            forVotes,
            parseEther("50000"),
        );

        assert.equal(
            abstainVotes,
            parseEther("50000"),
        );

        // Quorum is 4% of the 1,000,000 GOV supply.
        const quorum =
            await dao.read.quorum([
                snapshot,
            ]);

        assert.equal(
            quorum,
            parseEther("40000"),
        );

        // GovernorCountingSimple counts:
        //
        // For + Abstain
        //
        // toward quorum.
        assert.ok(
            forVotes + abstainVotes >= quorum,
        );

        const deadline =
            await dao.read.proposalDeadline([
                proposalId,
            ]);

        currentBlock =
            await publicClient.getBlockNumber();

        const blocksUntilFinished =
            deadline >= currentBlock
                ? deadline - currentBlock + 1n
                : 0n;

        if (blocksUntilFinished > 0n) {
            await networkHelpers.mine(
                Number(blocksUntilFinished),
            );
        }

        // 4 = Succeeded
        //
        // Abstain helped satisfy quorum,
        // but did not count as an Against vote.
        assert.equal(
            await dao.read.state([proposalId]),
            4,
        );
    });
});