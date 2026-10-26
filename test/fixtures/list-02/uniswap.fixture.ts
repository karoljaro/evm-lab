import { network } from "hardhat";
import { maxUint256, parseEther } from "viem";

export const connection = await network.create("hardhatMainnet");
export const { viem, networkHelpers } = connection;

export async function deployUniswapFixture() {
    const [provider, trader, recipient] = await viem.getWalletClients();
    if (provider === undefined || trader === undefined || recipient === undefined) {
        throw new Error("The local network needs three test accounts");
    }
    const publicClient = await viem.getPublicClient();
    const a = await viem.deployContract("LabToken", ["Token A", "A"]);
    const b = await viem.deployContract("LabToken", ["Token B", "B"]);
    const v1a = await viem.deployContract("MiniUniswapV1", [a.address]);
    const v1b = await viem.deployContract("MiniUniswapV1", [b.address]);
    const v2 = await viem.deployContract("MiniUniswapV2", [a.address, b.address]);
    const router = await viem.deployContract("MiniRouter");
    const reserve = parseEther("100");
    await a.write.mint([provider.account.address, reserve * 10n]);
    await b.write.mint([provider.account.address, reserve * 10n]);
    await a.write.mint([trader.account.address, reserve]);
    await a.write.approve([v1a.address, maxUint256]);
    await a.write.approve([v2.address, maxUint256]);
    await b.write.approve([v1b.address, maxUint256]);
    await b.write.approve([v2.address, maxUint256]);
    await v1a.write.addLiquidity([reserve, 0n, maxUint256], { value: reserve });
    await v1b.write.addLiquidity([reserve, 0n, maxUint256], { value: reserve });
    await v2.write.addLiquidity([reserve, reserve, 0n, 0n, 0n, maxUint256]);
    // Approval setup is outside the measured swaps; identical infinite user allowances.
    await a.write.approve([router.address, maxUint256], { account: trader.account });
    await a.write.approve([v1a.address, maxUint256], { account: trader.account });
    return { a, b, v1a, v1b, v2, router, provider, trader, recipient, publicClient, reserve };
}
