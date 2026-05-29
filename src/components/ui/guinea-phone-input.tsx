import * as React from "react";
import { cn } from "@/lib/utils";
import {
  GUINEA_DIAL_CODE,
  extractGuineaLocal,
  formatGuineaLocal,
} from "@/lib/phone/guinea";

interface GuineaPhoneInputProps {
  id?: string;
  /** Local digits only (no +224). */
  value: string;
  /** Receives local digits only (no +224, no spaces). */
  onChange: (localDigits: string) => void;
  required?: boolean;
  disabled?: boolean;
  className?: string;
  placeholder?: string;
  maxLength?: number;
}

/**
 * Phone field with a fixed +224 (Guinea) prefix. The user only types the
 * local number; pasted full numbers (224…, +224…, 00224…) are unwrapped
 * automatically so we never end up with `+224+224…`.
 */
export const GuineaPhoneInput = React.forwardRef<
  HTMLInputElement,
  GuineaPhoneInputProps
>(function GuineaPhoneInput(
  {
    id,
    value,
    onChange,
    required,
    disabled,
    className,
    placeholder = "622 12 34 56",
    maxLength = 12, // visual length incl. spaces for 9 digits
  },
  ref,
) {
  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const local = extractGuineaLocal(e.target.value).slice(0, 9);
    onChange(local);
  };

  return (
    <div
      className={cn(
        "flex h-10 w-full items-stretch rounded-md border border-input bg-background ring-offset-background focus-within:outline-none focus-within:ring-2 focus-within:ring-ring focus-within:ring-offset-2",
        disabled && "opacity-50",
        className,
      )}
    >
      <span
        aria-hidden="true"
        className="flex items-center px-3 text-sm font-medium text-foreground bg-muted/60 rounded-l-md border-r border-input select-none"
      >
        {GUINEA_DIAL_CODE}
      </span>
      <input
        ref={ref}
        id={id}
        type="tel"
        inputMode="tel"
        autoComplete="tel"
        value={formatGuineaLocal(value)}
        onChange={handleChange}
        placeholder={placeholder}
        required={required}
        disabled={disabled}
        maxLength={maxLength}
        className="flex-1 bg-transparent px-3 py-2 text-base outline-none placeholder:text-muted-foreground disabled:cursor-not-allowed md:text-sm rounded-r-md"
      />
    </div>
  );
});