import { network } from 'hardhat';

const { viem, networkHelpers } = await network.getOrCreate();

export async function deployGovernance(
    votingPeriod = 50_400,
    proposalThreshold = 0n,
) {
    const wallets = await viem.getWalletClients();

    if (wallets.length < 4)
        throw new Error("At least 4 test accounts are required");

    const accountA = wallets[0]!;
    const accountB = wallets[1]!;
    const accountC = wallets[2]!;
    const accountD = wallets[3]!;

    const publicClient = await viem.getPublicClient();

    const token = await viem.deployContract("GovToken");

    const dao = await viem.deployContract("MyDAO", [token.address, votingPeriod, proposalThreshold]);

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

export async function deployGovernanceFixture() {
    return deployGovernance();
}

export async function deployShortVotingGovernanceFixture() {
    return deployGovernance(5);
}

export { networkHelpers };