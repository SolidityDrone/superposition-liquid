import { BigInt } from "@graphprotocol/graph-ts";
import { SideSet, BorrowSet } from "../generated/MakerConfig/MakerConfig";
import { Maker, Side, BorrowConfig } from "../generated/schema";

function touchMaker(id: string): Maker {
  let maker = Maker.load(id);
  if (maker === null) {
    maker = new Maker(id);
    maker.fillCount = 0;
    maker.volumeIn = BigInt.fromI32(0);
    maker.save();
  }
  return maker as Maker;
}

export function handleSideSet(event: SideSet): void {
  const maker = touchMaker(event.params.maker.toHexString());
  const id = maker.id + "-" + event.params.underlying.toHexString();
  let side = Side.load(id);
  if (side === null) side = new Side(id);
  side.maker = maker.id;
  side.underlying = event.params.underlying;
  side.adapter = event.params.adapter;
  side.kind = event.params.kind;
  side.autoManaged = event.params.autoManaged;
  side.updatedAt = event.block.timestamp;
  side.save();
}

export function handleBorrowSet(event: BorrowSet): void {
  const maker = touchMaker(event.params.maker.toHexString());
  const id = maker.id + "-" + event.params.underlying.toHexString();
  let b = BorrowConfig.load(id);
  if (b === null) b = new BorrowConfig(id);
  b.maker = maker.id;
  b.underlying = event.params.underlying;
  b.collateral = event.params.collateral;
  b.maxDebt = event.params.maxDebt;
  b.updatedAt = event.block.timestamp;
  b.save();
}
