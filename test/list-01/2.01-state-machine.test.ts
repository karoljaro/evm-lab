import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
    encodeFunctionData,
    keccak256,
    stringToHex,
    type Address,
    type Hex
} from "viem";
import { deployGovernanceFixture, networkHelpers } from "../fixtures/list-01/governance.fixture.js";

describe("List 01 / Task 02.1 - Proposal state machine", () => {
    it("moves from Pending to Active to Defeated when nobody votes", async () => {
        const {
            token,
            dao,
            publicClient,
            accountC,
        } = await networkHelpers.loadFixture(deployGovernanceFixture);

        const description = "Wypłata 100 tokenów dla Konta 3(C)";

        const calldata = encodeFunctionData({
            abi: token.abi,
            functionName: "transfer",
            args: [accountC.account.address, 100n]
        });

        const targets: Address[] = [token.address];
        const values: bigint[] = [0n];
        const calldatas: Hex[] = [calldata];
        const descriptionHash = keccak256(stringToHex(description));
        const proposalId = await dao.read.hashProposal([
            targets,
            values,
            calldatas,
            descriptionHash
        ]);

        const proposeHash = await dao.write.propose([
            targets,
            values,
            calldatas,
            description
        ]);

        await publicClient.waitForTransactionReceipt({ hash: proposeHash });

        assert.equal(
            await dao.read.state([proposalId]),
            0
        )

        const snapshot = await dao.read.proposalSnapshot([proposalId]);

        let currentBlock = await publicClient.getBlockNumber();

        const blocksUntilActive = snapshot >= currentBlock ? snapshot - currentBlock + 1n : 0n;

        if (blocksUntilActive > 0n) {
            await networkHelpers.mine(
                Number(blocksUntilActive)
            );
        }

        assert.equal(
            await dao.read.state([proposalId]),
            1
        );

        const deadline = await dao.read.proposalDeadline([proposalId]);

        currentBlock = await publicClient.getBlockNumber();

        const blocksUntilDeadline = deadline >= currentBlock ? deadline - currentBlock + 1n : 0n;

        if (blocksUntilDeadline > 0n) {
            await networkHelpers.mine(
                Number(blocksUntilDeadline)
            );
        }

        assert.equal(
            await dao.read.state([proposalId]),
            3
        );
    })
})