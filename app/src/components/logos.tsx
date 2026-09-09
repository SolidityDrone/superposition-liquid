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

export function LidoLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <path d="M12 2l3.2 3.2L12 8.4 8.8 5.2z" fill="#35a3ff" />
      <path d="M18.8 8.8L22 12l-3.2 3.2-3.2-3.2z" fill="#35a3ff" />
      <path d="M5.2 8.8L8.4 12l-3.2 3.2L2 12z" fill="#35a3ff" />
      <path d="M12 15.6l3.2 3.2L12 22l-3.2-3.2z" fill="#35a3ff" />
      <path d="M8.8 8.8h6.4v6.4H8.8z" fill="#7cc4ff" />
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

export function CurveLogo({ size = 16 }: SvgProps) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden>
      <path
        d="M17 7.2C15.9 5.8 14.1 5 12.2 5 8.5 5 5.6 8.1 5.6 12s2.9 7 6.6 7c1.9 0 3.7-.8 4.8-2.2"
        stroke="#f5d020"
        strokeWidth="3"
        fill="none"
        strokeLinecap="round"
      />
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

export function StakingIcon({ size = 20 }: SvgProps) {
  return (
    <LineIcon size={size}>
      <path d="M10 2.4c3.4 3.9 5.8 6.3 5.8 9.1a5.8 5.8 0 1 1-11.6 0c0-2.8 2.4-5.2 5.8-9.1z" />
      <path d="M7.4 11.6a2.6 2.6 0 0 0 2.6 2.6" />
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
