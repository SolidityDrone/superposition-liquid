const SIZES = 14;

/**
 * Deterministic pseudo-random glow pattern for the tile-grid background
 * (parestocks-style: mostly dim tiles, a few glowing accents, seeded so
 * the server and client render identically).
 */
function glowKind(row: number, col: number): 0 | 1 | 2 | 3 | 4 {
  const h = (row * 73856093) ^ (col * 19349663);
  const r = ((h >>> 16) ^ h) & 0xff;
  if (r > 244) return 3; // full glow
  if (r > 225) return 2; // soft glow
  if (r > 190) return 1; // faint
  if (r < 60) return 4; // invisible (density control)
  return 0; // barely visible
}

export default function TileBackground({ opacity = 1 }: { opacity?: number }) {
  const cells = [];
  for (let row = 0; row < SIZES; row++) {
    for (let col = 0; col < SIZES; col++) {
      const k = glowKind(row, col);
      const cls = k === 0 ? "tile" : k === 4 ? "tile fade" : `tile g${k}`;
      cells.push(<div key={`${row}-${col}`} className={cls} />);
    }
  }
  return (
    <div className="tile-bg" aria-hidden style={{ opacity }}>
      <div className="tile-grid" style={{ gridTemplateColumns: `repeat(${SIZES}, 38px)` }}>
        {cells}
      </div>
    </div>
  );
}
