import { BigInt } from "@graphprotocol/graph-ts";
import { Deposited, Withdrawn } from "../generated/SuperpositionHook/SuperpositionHook";
import { HookBucketFlow } from "../generated/schema";

export function handleHookDeposited(event: Deposited): void {
  const f = new HookBucketFlow(event.transaction.hash.concatI32(event.logIndex.toI32()));
  f.hook = event.address;
  f.kind = "deposit";
  f.recipient = event.params.recipient;
  f.lower = event.params.lower;
  f.upper = event.params.upper;
  f.amount0 = event.params.amount0;
  f.amount1 = event.params.amount1;
  f.shares = event.params.shares;
  f.blockNumber = event.block.number;
  f.timestamp = event.block.timestamp;
  f.txHash = event.transaction.hash;
  f.save();
}

export function handleHookWithdrawn(event: Withdrawn): void {
  const f = new HookBucketFlow(event.transaction.hash.concatI32(event.logIndex.toI32()));
  f.hook = event.address;
  f.kind = "withdraw";
  f.recipient = event.params.recipient;
  f.lower = event.params.lower;
  f.upper = event.params.upper;
  f.amount0 = event.params.amount0;
  f.amount1 = event.params.amount1;
  f.shares = event.params.shares;
  f.blockNumber = event.block.number;
  f.timestamp = event.block.timestamp;
  f.txHash = event.transaction.hash;
  f.save();
}
