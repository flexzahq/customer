import { Drawer, DrawerContent, DrawerHeader, DrawerTitle } from "@/components/ui/drawer";
import { Card, CardContent } from "@/components/ui/card";

interface TimingDrawerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export const TimingDrawer = ({ open, onOpenChange }: TimingDrawerProps) => {
  return (
    <Drawer open={open} onOpenChange={onOpenChange}>
      <DrawerContent>
        <DrawerHeader>
          <DrawerTitle>Timing</DrawerTitle>
          <p className="text-sm text-muted-foreground">See opening hours below</p>
        </DrawerHeader>

        <div className="p-6 space-y-4">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-primary rounded-full flex items-center justify-center shrink-0 mt-1">
                  <div className="w-2 h-2 bg-primary-foreground rounded-full" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold mb-2">Morning Time</p>
                  <p className="text-2xl font-bold">10:00 AM – 1:00 PM</p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-primary rounded-full flex items-center justify-center shrink-0 mt-1">
                  <div className="w-2 h-2 bg-primary-foreground rounded-full" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold mb-2">Evening Time</p>
                  <p className="text-2xl font-bold">5:00 PM – 8:00 PM</p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </DrawerContent>
    </Drawer>
  );
};
