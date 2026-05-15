import { useTheme } from "next-themes";
import { Toaster as Sonner, toast } from "sonner";

type ToasterProps = React.ComponentProps<typeof Sonner>;

const Toaster = ({ ...props }: ToasterProps) => {
  const { theme = "system" } = useTheme();

  return (
    <Sonner
      theme={theme as ToasterProps["theme"]}
      className="toaster group"
      position="bottom-center"
      duration={4000}
      gap={10}
      offset={96}
      mobileOffset={96}
      visibleToasts={3}
      expand={false}
      toastOptions={{
        duration: 4000,
        classNames: {
          toast:
            "group toast w-full max-w-[calc(100vw-1.5rem)] sm:max-w-sm rounded-2xl px-4 py-3 gap-3 group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border group-[.toaster]:border-border group-[.toaster]:shadow-elevated",
          title: "text-sm font-semibold leading-snug",
          description: "group-[.toast]:text-muted-foreground",
          actionButton: "group-[.toast]:bg-primary group-[.toast]:text-primary-foreground",
          cancelButton: "group-[.toast]:bg-muted group-[.toast]:text-muted-foreground",
          success:
            "group-[.toaster]:!border-l-4 group-[.toaster]:!border-l-primary",
          error:
            "group-[.toaster]:!border-l-4 group-[.toaster]:!border-l-destructive",
          warning:
            "group-[.toaster]:!border-l-4 group-[.toaster]:!border-l-secondary",
          info:
            "group-[.toaster]:!border-l-4 group-[.toaster]:!border-l-accent",
        },
      }}
      {...props}
    />
  );
};

export { Toaster, toast };
