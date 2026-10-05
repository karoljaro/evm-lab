import assert from "node:assert/strict";
import { after, describe, it } from "node:test";

import { network } from "hardhat";

const connection = await network.create();
const { viem, networkHelpers } = connection;

describe("Counter: TypeScript + viem", function () {
  after(async function () {
    await connection.close();
  });

  async function deployCounterFixture() {
    const counter = await viem.deployContract("Counter");
    const publicClient = await viem.getPublicClient();

    return { counter, publicClient };
  }

  it("emits an Increment event and updates the value", async function () {
    const { counter } = await networkHelpers.loadFixture(deployCounterFixture);

    assert.equal(await counter.read.value(), 0n);
    await viem.assertions.emitWithArgs(
      counter.write.inc(),
      counter,
      "Increment",
      [1n],
    );
    assert.equal(await counter.read.value(), 1n);
  });

  it("matches transaction events with the state read at the deployed address", async function () {
    const { counter, publicClient } =
      await networkHelpers.loadFixture(deployCounterFixture);
    const fromBlock = await publicClient.getBlockNumber();

    for (const amount of [2n, 3n, 5n]) {
      const hash = await counter.write.incBy([amount]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      assert.equal(receipt.status, "success");
    }

    const events = await publicClient.getContractEvents({
      address: counter.address,
      abi: counter.abi,
      eventName: "Increment",
      fromBlock,
      strict: true,
    });
    assert.deepEqual(events.map((event) => event.args.amount), [2n, 3n, 5n]);

    const total = events.reduce((sum, event) => sum + event.args.amount, 0n);
    const deployedCounter = await viem.getContractAt("Counter", counter.address);
    assert.equal(total, 10n);
    assert.equal(await deployedCounter.read.value(), total);
  });

  it("rejects a zero increment with a custom error", async function () {
    const { counter } = await networkHelpers.loadFixture(deployCounterFixture);

    await viem.assertions.revertWithCustomError(
      counter.write.incBy([0n]),
      counter,
      "ZeroIncrement",
    );
    assert.equal(await counter.read.value(), 0n);
  });
});
