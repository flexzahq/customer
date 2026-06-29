import { Drawer, DrawerContent } from "@/components/ui/drawer";
import { Button } from "@/components/ui/button";
import { Check } from "lucide-react";

interface BookingSuccessDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  tokenNumber: number;
}

export const BookingSuccessDialog = ({ open, onOpenChange, tokenNumber }: BookingSuccessDialogProps) => {
  return (
    <Drawer open={open} onOpenChange={onOpenChange}>
      <DrawerContent>
        <div className="p-8 text-center space-y-6">
          <div className="relative w-32 h-32 mx-auto">
            <div className="absolute inset-0">
              <svg viewBox="0 0 100 100" className="w-full h-full">
                <path
                  d="M10,50 Q10,20 30,10 L70,10 Q90,20 90,50 Q90,80 70,90 L30,90 Q10,80 10,50"
                  fill="none"
                  stroke="hsl(var(--muted))"
                  strokeWidth="2"
                />
                <path
                  d="M5,50 Q5,50 15,45 L20,40"
                  fill="none"
                  stroke="hsl(var(--muted))"
                  strokeWidth="2"
                />
                <path
                  d="M95,50 Q95,50 85,45 L80,40"
                  fill="none"
                  stroke="hsl(var(--muted))"
                  strokeWidth="2"
                />
              </svg>
            </div>
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="w-24 h-24 bg-primary rounded-full flex items-center justify-center">
                <Check className="w-12 h-12 text-primary-foreground" strokeWidth={3} />
              </div>
            </div>
          </div>

          <div>
            <h2 className="text-2xl font-bold mb-2">
              Token <span className="text-primary">#{tokenNumber}</span>
            </h2>
            <p className="text-xl font-bold mb-1">booked successfully.</p>
            <p className="text-sm text-muted-foreground">
              We'll notify you when your turn is near.
            </p>
          </div>

          <Button
            onClick={() => onOpenChange(false)}
            className="w-full max-w-xs mx-auto h-12 rounded-xl"
          >
            Back to Home
          </Button>
        </div>
      </DrawerContent>
    </Drawer>
  );
};
