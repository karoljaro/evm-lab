import { network } from 'hardhat';

const { viem, networkHelpers } = await network.getOrCreate();

export async function deployGovernanceFixture() {
    const wallets = await viem.getWalletClients();

    if (wallets.length < 4)
        throw new Error("At least 4 test accounts are required");

    const accountA = wallets[0]!;
    const accountB = wallets[1]!;
    const accountC = wallets[2]!;
    const accountD = wallets[3]!;

    const publicClient = await viem.getPublicClient();

    const token = await viem.deployContract("GovToken");

    const dao = await viem.deployContract("MyDAO", [token.address]);

    return {
        token,
        dao,
        publicClient,
        accountA,
        accountB,
        accountC,
        accountD
    }
}

export { networkHelpers };