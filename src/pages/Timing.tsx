import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Clock } from "lucide-react";

const Timing = () => {
  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">Timing</h1>
        <p className="text-sm text-muted-foreground">See opening hours below</p>

        <div className="space-y-4">
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
      </div>

      <BottomNav variant="patient" />
    </div>
  );
};

export default Timing;
