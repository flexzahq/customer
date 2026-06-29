import { Card } from "@/components/ui/card";
import { Users, Clock } from "lucide-react";

interface QueueStatsProps {
  totalAhead: number;
  estimatedTime: string;
}

export const QueueStats = ({ totalAhead, estimatedTime }: QueueStatsProps) => {
  return (
    <div className="space-y-3">
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Users className="w-5 h-5" />
            <span className="font-semibold">Total ahead</span>
          </div>
          <span className="text-2xl font-semibold">{totalAhead}</span>
        </div>
      </Card>
      <Card className="p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Clock className="w-5 h-5" /> 
            <span className="font-semibold">Estimated Time</span>
          </div>
          <span className="text-2xl font-bold">{estimatedTime}</span>
        </div>
      </Card>
    </div>
  );
};
