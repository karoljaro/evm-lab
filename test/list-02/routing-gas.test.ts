import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { after, describe, it } from "node:test";
import { artifacts } from "hardhat";
import type { BuildInfo } from "hardhat/types/artifacts";
import { formatEther, keccak256, maxUint256, parseEther, stringToHex, type Hex } from "viem";
import { connection, deployUniswapFixture, networkHelpers } from "../fixtures/list-02/uniswap.fixture.js";

const quote = (input: bigint, reserveIn: bigint, reserveOut: bigint) =>
    input * 997n * reserveOut / (reserveIn * 1000n + input * 997n);
const transferTopic = keccak256(stringToHex("Transfer(address,address,uint256)"));
const scenarios = [
    { name: "equal-pool-reserves-zero-recipient", existingRecipient: false, halfV2: false },
    { name: "equal-pool-reserves-existing-recipient", existingRecipient: true, halfV2: false },
    { name: "matched-no-fee-depth-zero-recipient", existingRecipient: false, halfV2: true },
] as const;

after(async () => connection.close());

describe("List 02 / Routing and measured transaction gas", () => {
    it("compares two V1 pools with direct V2 using isolated transaction receipts", async (t) => {
        const samples = [];
        for (const scenario of scenarios) {
            const f = await networkHelpers.loadFixture(deployUniswapFixture);
            const { a, b, v1a, v1b, v2, router, trader, recipient, publicClient, reserve } = f;
            if (scenario.existingRecipient) await b.write.mint([recipient.account.address, 1n]);
            if (scenario.halfV2) {
                await v2.write.removeLiquidity([reserve / 2n, 0n, 0n, f.provider.account.address, maxUint256]);
            }
            const baseline = await networkHelpers.takeSnapshot();
            const input = parseEther("1");
            const recipientBefore = await b.read.balanceOf([recipient.account.address]);
            const traderBefore = await a.read.balanceOf([trader.account.address]);
            const eth = quote(input, reserve, reserve);
            const expectedV1 = quote(eth, reserve, reserve);
            const v2Reserve = scenario.halfV2 ? reserve / 2n : reserve;
            const expectedV2 = quote(input, v2Reserve, v2Reserve);

            async function receipt(hash: Hex) {
                const mined = await publicClient.waitForTransactionReceipt({ hash });
                assert.equal(mined.status, "success");
                assert.ok(mined.gasUsed > 21_000n);
                return mined;
            }

            const atomicV1 = await receipt(await router.write.swapV1ToV1(
                [v1a.address, v1b.address, input, 0n, 0n, recipient.account.address, maxUint256],
                { account: trader.account },
            ));
            assert.equal(await b.read.balanceOf([recipient.account.address]) - recipientBefore, expectedV1);
            assert.equal(traderBefore - await a.read.balanceOf([trader.account.address]), input);
            assert.equal(await publicClient.getBalance({ address: router.address }), 0n);
            assert.equal(await a.read.balanceOf([router.address]), 0n);
            const atomicV1Transfers = atomicV1.logs.filter((log) => log.topics[0] === transferTopic).length;
            assert.equal(atomicV1Transfers, 3);

            // Revert all V1 writes: recipient balance and allowances must match for V2.
            await baseline.restore();
            const directV2 = await receipt(await router.write.swapV2(
                [v2.address, true, input, 0n, recipient.account.address, maxUint256],
                { account: trader.account },
            ));
            assert.equal(await b.read.balanceOf([recipient.account.address]) - recipientBefore, expectedV2);
            assert.equal(traderBefore - await a.read.balanceOf([trader.account.address]), input);
            const v2Transfers = directV2.logs.filter((log) => log.topics[0] === transferTopic).length;
            assert.equal(v2Transfers, 2);
            assert.ok(expectedV1 < expectedV2);

            await baseline.restore();
            const hop1 = await receipt(await v1a.write.tokenToEthSwap(
                [input, 0n, trader.account.address, maxUint256], { account: trader.account },
            ));
            const hop2 = await receipt(await v1b.write.ethToTokenSwap(
                [0n, recipient.account.address, maxUint256], { account: trader.account, value: eth },
            ));
            assert.equal(await b.read.balanceOf([recipient.account.address]) - recipientBefore, expectedV1);
            const twoTransactionGas = hop1.gasUsed + hop2.gasUsed;
            const sample = {
                scenario: scenario.name,
                inputA: formatEther(input),
                v1EachPoolTokenReserve: formatEther(reserve),
                v1EachPoolEthReserve: formatEther(reserve),
                v2EachTokenReserve: formatEther(v2Reserve),
                v1AtomicGas: atomicV1.gasUsed.toString(),
                v1Hop1Gas: hop1.gasUsed.toString(),
                v1Hop2Gas: hop2.gasUsed.toString(),
                v1TwoTransactionsGas: twoTransactionGas.toString(),
                v2AtomicGas: directV2.gasUsed.toString(),
                v1AtomicMinusV2Gas: (atomicV1.gasUsed - directV2.gasUsed).toString(),
                v1TwoTransactionsMinusV2Gas: (twoTransactionGas - directV2.gasUsed).toString(),
                v1AtomicErc20Transfers: atomicV1Transfers,
                v2AtomicErc20Transfers: v2Transfers,
                v1OutputB: formatEther(expectedV1),
                v2OutputB: formatEther(expectedV2),
                transactionHashes: [atomicV1.transactionHash, directV2.transactionHash, hop1.transactionHash, hop2.transactionHash],
            };
            samples.push(sample);
            t.diagnostic(`${sample.scenario}: V1 router=${sample.v1AtomicGas}, V1 2 tx=${sample.v1TwoTransactionsGas}, V2 router=${sample.v2AtomicGas} gas`);
        }

        if (process.env.LIST02_GAS_REPORT === "1") {
            const buildId = await artifacts.getBuildInfoId("MiniUniswapV2");
            assert.ok(buildId);
            const buildPath = await artifacts.getBuildInfoPath(buildId);
            assert.ok(buildPath);
            const build = JSON.parse(await readFile(buildPath, "utf8")) as BuildInfo;
            const hardhatPackage = JSON.parse(await readFile("node_modules/hardhat/package.json", "utf8")) as { version: string };
            const viemPackage = JSON.parse(await readFile("node_modules/viem/package.json", "utf8")) as { version: string };
            const sourceFiles = [
                "hardhat.config.ts", "package.json", "bun.lock",
                "contracts/list-02/PoolMath.sol", "contracts/list-02/PoolShares.sol",
                "contracts/list-02/MiniUniswapV1.sol", "contracts/list-02/MiniUniswapV2.sol",
                "contracts/list-02/MiniRouter.sol", "contracts/list-02/mocks/TestTokens.sol",
                "test/fixtures/list-02/uniswap.fixture.ts", "test/list-02/routing-gas.test.ts",
            ];
            const sourceSha256: Record<string, string> = {};
            for (const file of sourceFiles) {
                sourceSha256[file] = createHash("sha256").update(await readFile(file)).digest("hex");
            }
            const report = {
                measuredAt: new Date().toISOString(),
                environment: {
                    node: process.versions.node,
                    bunLauncher: /bun\/(\S+)/.exec(process.env.npm_config_user_agent ?? "")?.[1] ?? "unknown",
                    hardhat: hardhatPackage.version,
                    viem: viemPackage.version,
                    solc: build.solcLongVersion,
                    compilerBuildId: buildId,
                    evmVersion: build.input.settings.evmVersion,
                    optimizer: build.input.settings.optimizer,
                    network: connection.networkName,
                    hardfork: connection.networkConfig.type === "edr-simulated" ? connection.networkConfig.hardfork : "unknown",
                    chainType: connection.chainType,
                },
                method: "Mined transactionReceipt.gasUsed; fresh snapshot for each path, no fork, no deployment/mint/seed/user-approval costs; includes intrinsic gas, refunds, and V1 router forceApprove. No timing measurements.",
                sourceSha256,
                samples,
            };
            await mkdir("docs/list-02", { recursive: true });
            await writeFile("docs/list-02/gas-measurements.json", `${JSON.stringify(report, null, 2)}\n`);
            t.diagnostic("Saved docs/list-02/gas-measurements.json");
        }
    });
});
