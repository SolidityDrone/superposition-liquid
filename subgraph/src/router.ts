import { BigInt } from "@graphprotocol/graph-ts";
import { Swapped } from "../generated/SuperPositionVMRouter/SuperPositionVMRouter";
import { Fill, Maker } from "../generated/schema";

export function handleSwapped(event: Swapped): void {
  const makerId = event.params.maker.toHexString();
  let maker = Maker.load(makerId);
  if (maker === null) {
    maker = new Maker(makerId);
    maker.fillCount = 0;
    maker.volumeIn = BigInt.fromI32(0);
  }
  maker.fillCount = maker.fillCount + 1;
  maker.volumeIn = maker.volumeIn.plus(event.params.amountIn);
  maker.save();

  const fill = new Fill(event.transaction.hash.concatI32(event.logIndex.toI32()));
  fill.orderHash = event.params.orderHash;
  fill.maker = maker.id;
  fill.taker = event.params.taker;
  fill.tokenIn = event.params.tokenIn;
  fill.tokenOut = event.params.tokenOut;
  fill.amountIn = event.params.amountIn;
  fill.amountOut = event.params.amountOut;
  fill.blockNumber = event.block.number;
  fill.timestamp = event.block.timestamp;
  fill.txHash = event.transaction.hash;
  fill.save();
}
