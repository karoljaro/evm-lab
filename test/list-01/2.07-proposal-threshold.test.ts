import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
    encodeFunctionData,
    parseEther,
    type Address,
    type Hex,
} from "viem";

import {
    deployProposalThresholdFixture,
    networkHelpers,
} from "../fixtures/list-01/governance.fixture.js";

describe("List 01 / Task 02.7 - Proposal threshold", () => {
    it("prevents an account with only 100 GOV of voting power from creating a proposal", async () => {
        const {
            token,
            dao,
            publicClient,
            accountA,
            accountB,
            accountC,
        } = await networkHelpers.loadFixture(
            deployProposalThresholdFixture,
        );

        assert.equal(
            await dao.read.proposalThreshold(),
            parseEther("1000"),
        );

        const transferHash =
            await token.write.transfer(
                [
                    accountB.account.address,
                    parseEther("100"),
                ],
                {
                    account: accountA.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: transferHash,
        });

        assert.equal(
            await token.read.balanceOf([
                accountB.account.address,
            ]),
            parseEther("100"),
        );

        const delegateHash =
            await token.write.delegate(
                [accountB.account.address],
                {
                    account: accountB.account,
                },
            );

        await publicClient.waitForTransactionReceipt({
            hash: delegateHash,
        });

        assert.equal(
            await token.read.getVotes([
                accountB.account.address,
            ]),
            parseEther("100"),
        );

        await networkHelpers.mine(1);

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

        await assert.rejects(async () => {
            await dao.write.propose(
                [
                    targets,
                    values,
                    calldatas,
                    description,
                ],
                {
                    account: accountB.account,
                },
            );
        });
    });
});