import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import { Deposit, Withdraw } from "../generated/VaultUSDC/ERC4626";
import { Vault, VaultFlow } from "../generated/schema";

function loadVault(addr: Bytes): Vault {
  const id = addr.toHexString();
  let v = Vault.load(id);
  if (v === null) {
    v = new Vault(id);
    v.asset = Bytes.empty();
    v.deposits = 0;
    v.withdrawals = 0;
    v.totalAssetsIn = BigInt.fromI32(0);
    v.totalAssetsOut = BigInt.fromI32(0);
    v.lastFlowAt = BigInt.fromI32(0);
    v.save();
  }
  return v as Vault;
}

export function handleDeposit(event: Deposit): void {
  const v = loadVault(event.address);
  v.deposits = v.deposits + 1;
  v.totalAssetsIn = v.totalAssetsIn.plus(event.params.assets);
  v.lastFlowAt = event.block.timestamp;
  v.save();

  const flow = new VaultFlow(event.transaction.hash.concatI32(event.logIndex.toI32()));
  flow.vault = v.id;
  flow.kind = "deposit";
  flow.sender = event.params.sender;
  flow.owner = event.params.owner;
  flow.assets = event.params.assets;
  flow.shares = event.params.shares;
  flow.blockNumber = event.block.number;
  flow.timestamp = event.block.timestamp;
  flow.txHash = event.transaction.hash;
  flow.save();
}

export function handleWithdraw(event: Withdraw): void {
  const v = loadVault(event.address);
  v.withdrawals = v.withdrawals + 1;
  v.totalAssetsOut = v.totalAssetsOut.plus(event.params.assets);
  v.lastFlowAt = event.block.timestamp;
  v.save();

  const flow = new VaultFlow(event.transaction.hash.concatI32(event.logIndex.toI32()));
  flow.vault = v.id;
  flow.kind = "withdraw";
  flow.sender = event.params.sender;
  flow.owner = event.params.owner;
  flow.assets = event.params.assets;
  flow.shares = event.params.shares;
  flow.blockNumber = event.block.number;
  flow.timestamp = event.block.timestamp;
  flow.txHash = event.transaction.hash;
  flow.save();
}
