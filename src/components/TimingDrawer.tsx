import { Drawer, DrawerContent, DrawerHeader, DrawerTitle } from "@/components/ui/drawer";
import { Card, CardContent } from "@/components/ui/card";
import { formatTimeRange } from "@/lib/clinicProfile";

interface TimingDrawerProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  morningStart?: string | null;
  morningEnd?: string | null;
  eveningStart?: string | null;
  eveningEnd?: string | null;
  loading?: boolean;
}

export const TimingDrawer = ({
  open,
  onOpenChange,
  morningStart,
  morningEnd,
  eveningStart,
  eveningEnd,
  loading,
}: TimingDrawerProps) => {
  const morning = formatTimeRange(morningStart, morningEnd);
  const evening = formatTimeRange(eveningStart, eveningEnd);

  return (
    <Drawer open={open} onOpenChange={onOpenChange}>
      <DrawerContent>
        <DrawerHeader>
          <DrawerTitle>Timing</DrawerTitle>
          <p className="text-sm text-muted-foreground">Clinic opening hours</p>
        </DrawerHeader>

        <div className="p-6 space-y-4">
          {loading && (
            <p className="text-sm text-muted-foreground">Loading timings…</p>
          )}
          {!loading && !morning && !evening && (
            <p className="text-sm text-muted-foreground">
              Timings not set yet. Ask the clinic to update hours.
            </p>
          )}
          {morning && (
            <Card>
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className="w-6 h-6 bg-primary rounded-full flex items-center justify-center shrink-0 mt-1">
                    <div className="w-2 h-2 bg-primary-foreground rounded-full" />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold mb-2">Morning Time</p>
                    <p className="text-2xl font-bold">{morning}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}
          {evening && (
            <Card>
              <CardContent className="p-4">
                <div className="flex items-start gap-3">
                  <div className="w-6 h-6 bg-primary rounded-full flex items-center justify-center shrink-0 mt-1">
                    <div className="w-2 h-2 bg-primary-foreground rounded-full" />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold mb-2">Evening Time</p>
                    <p className="text-2xl font-bold">{evening}</p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}
        </div>
      </DrawerContent>
    </Drawer>
  );
};
