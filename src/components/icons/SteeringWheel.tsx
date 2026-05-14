import { SVGProps } from "react";

/**
 * SteeringWheel — soft, rounded, mobility-focused glyph.
 * Designed to match the Lucide stroke system (24x24, stroke-2, round caps/joins)
 * so it sits naturally next to other CHOP CHOP nav icons.
 */
export function SteeringWheel({
  size = 24,
  strokeWidth = 2,
  ...props
}: SVGProps<SVGSVGElement> & { size?: number | string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      {...props}
    >
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2" />
      <path d="M12 10V5" />
      <path d="M10.3 13a2 2 0 0 0-1.7 1l-2.5 4" />
      <path d="M13.7 13a2 2 0 0 1 1.7 1l2.5 4" />
    </svg>
  );
}

export default SteeringWheel;