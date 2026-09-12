/**
 * Inline SVG logos (simplified brand marks) and category icons.
 * All server-renderable, no external assets, no network fetches.
 */

type SvgProps = { size?: number };

/* ---------------- protocol logos ---------------- */

export function AaveLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <defs>
        <linearGradient id="sg-aave" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#B6509E" />
          <stop offset="1" stopColor="#2CA8E0" />
        </linearGradient>
      </defs>
      <circle cx="12" cy="12" r="12" fill="url(#sg-aave)" />
      <path
        d="M12 4.6c.62 0 1.18.37 1.42.94l4.72 10.7c.36.82-.24 1.76-1.14 1.76H7c-.9 0-1.5-.94-1.14-1.76l4.72-10.7c.24-.57.8-.94 1.42-.94z"
        fill="#fff"
      />
      <circle cx="9.9" cy="13.6" r="1.15" fill="url(#sg-aave)" />
      <circle cx="14.1" cy="13.6" r="1.15" fill="url(#sg-aave)" />
    </svg>
  );
}

export function MorphoLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <path d="M7.2 4h9.6l4.2 5.2L12 21 3 9.2z" fill="#1b5cff" />
      <path d="M12 21 8.6 9.2h6.8L12 21z" fill="#4d7dff" />
      <path d="M7.2 4 8.6 9.2h6.8L16.8 4H7.2z" fill="#7aa3ff" />
    </svg>
  );
}

export function EulerLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="12" fill="#14aeea" />
      <path
        d="M16.5 8.2c-.9-1.1-2.4-1.8-4-1.8-3 0-5.4 2.5-5.4 5.6s2.4 5.6 5.4 5.6c1.6 0 3.1-.7 4-1.8"
        stroke="#fff"
        strokeWidth="2.4"
        fill="none"
        strokeLinecap="round"
      />
      <path d="M7.5 11h5" stroke="#fff" strokeWidth="2.4" strokeLinecap="round" />
    </svg>
  );
}

export function PendleLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <defs>
        <linearGradient id="sg-pendle" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#6c5ce7" />
          <stop offset="1" stopColor="#2c3e9e" />
        </linearGradient>
      </defs>
      <circle cx="12" cy="12" r="10.5" fill="url(#sg-pendle)" />
      <ellipse
        cx="12"
        cy="12"
        rx="7.2"
        ry="3.2"
        stroke="#cfd6ff"
        strokeWidth="1.4"
        fill="none"
        transform="rotate(-24 12 12)"
      />
      <circle cx="17.4" cy="8.2" r="2" fill="#cfd6ff" />
    </svg>
  );
}

export function StargateLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <path d="M12 2l2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4z" fill="#4c6fff" />
      <circle cx="12" cy="12" r="2.2" fill="#c7d6ff" />
    </svg>
  );
}

export function USDCLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="12" fill="#2775CA" />
      <path
        d="M14.8 13.9c0-1-.6-1.7-2-2.2-.95-.35-1.35-.6-1.35-1.05 0-.5.45-.85 1.2-.85.75 0 1.25.3 1.5.95l1.45-.85c-.45-.95-1.3-1.5-2.4-1.65V7.1h-1.4v1.15c-1.4.2-2.45 1.1-2.45 2.4 0 1.05.65 1.8 2.05 2.3 1 .35 1.4.65 1.4 1.1 0 .55-.5.9-1.3.9-.85 0-1.45-.4-1.7-1.1l-1.5.9c.4 1 1.35 1.65 2.45 1.8v1.2h1.4v-1.2c1.55-.2 2.6-1.15 2.6-2.45z"
        fill="#fff"
      />
      <path
        d="M10.2 5.1a7.1 7.1 0 0 0 0 13.8M13.8 18.9a7.1 7.1 0 0 0 0-13.8"
        stroke="#fff"
        strokeWidth="1.1"
        fill="none"
        strokeLinecap="round"
      />
    </svg>
  );
}

export function ETHLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="12" fill="#627EEA" />
      <path d="M12 3.4 7.6 11.3 12 13.7z" fill="#fff" opacity=".6" />
      <path d="M12 3.4l4.4 7.9-4.4-2.4z" fill="#fff" />
      <path d="M7.6 13.1 12 15.5v5.1z" fill="#fff" opacity=".6" />
      <path d="M16.4 13.1 12 15.5v5.1z" fill="#fff" />
      <path d="M12 8.3 7.6 11.3l4.4 2.4z" fill="#fff" opacity=".25" />
      <path d="M16.4 11.3 12 8.3v5.4z" fill="#fff" opacity=".25" />
    </svg>
  );
}

/* ---------------- category icons (line style) ---------------- */

function LineIcon({ size = 20, children }: { size?: number; children: React.ReactNode }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {children}
    </svg>
  );
}

export function LendingIcon({ size = 20 }: SvgProps) {
  return (
    <LineIcon size={size}>
      <ellipse cx="10" cy="5" rx="7" ry="2.8" />
      <path d="M3 5v5c0 1.55 3.13 2.8 7 2.8s7-1.25 7-2.8V5" />
      <path d="M3 10v5c0 1.55 3.13 2.8 7 2.8s7-1.25 7-2.8v-5" />
    </LineIcon>
  );
}

export function VaultIcon({ size = 20 }: SvgProps) {
  return (
    <LineIcon size={size}>
      <rect x="3" y="3" width="14" height="14" rx="2.5" />
      <circle cx="10" cy="10" r="3" />
      <path d="M10 5.4V7M10 13v1.6M14.6 10H13M7 10H5.4" />
    </LineIcon>
  );
}

export function FixedIncomeIcon({ size = 20 }: SvgProps) {
  return (
    <LineIcon size={size}>
      <path d="M3 16.5h14" />
      <path d="M4 12.8l4.2-4.2 3 2 4.8-5.4" />
      <path d="M12.6 5.2h3.4v3.4" />
    </LineIcon>
  );
}

export function BridgeIcon({ size = 20 }: SvgProps) {
  return (
    <LineIcon size={size}>
      <path d="M2.6 14.5v-1.4a7.4 7.4 0 0 1 14.8 0v1.4" />
      <path d="M2.6 14.5h14.8" />
      <path d="M6 14.5V17M14 14.5V17M10 10.4V17" />
    </LineIcon>
  );
}

/* ---------------- Uniswap v4 / hook ---------------- */

export function UniswapLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="12" fill="#ff37c7" />
      <text
        x="12"
        y="16.4"
        textAnchor="middle"
        fontSize="11"
        fontWeight="800"
        fill="#0b1420"
        fontFamily="system-ui, sans-serif"
      >
        v4
      </text>
    </svg>
  );
}

export function HookIcon({ size = 20 }: SvgProps) {
  return (
    <LineIcon size={size}>
      <path d="M10 2.6v8.2" />
      <path d="M7.2 5.4h5.6" />
      <path d="M10 10.8a4.4 4.4 0 0 1 4.4 4.4v.6a3 3 0 0 1-3 3 3 3 0 0 1-3-3" />
    </LineIcon>
  );
}
