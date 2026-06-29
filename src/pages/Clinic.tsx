import { Header } from "@/components/Header";
import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Users, CreditCard, ChevronRight } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";

const Clinic = () => {
  return (
    <div className="min-h-screen bg-background pb-20">
      <Header userInitials="NA" />

      <div className="p-4 space-y-6">
        {/* Stats Card */}
        <Card>
          <CardContent className="p-6">
            <div className="flex items-start justify-between mb-6">
              <div>
                <h2 className="text-4xl font-bold">1000</h2>
                <p className="text-sm text-muted-foreground">Total Tokens</p>
              </div>
              <Button variant="outline" size="sm" className="rounded-full">
                This Month
              </Button>
            </div>

            {/* Chart Area */}
            <div className="h-40 bg-gradient-to-b from-primary/5 to-primary/20 rounded-lg mb-6 relative overflow-hidden">
              <svg className="w-full h-full" viewBox="0 0 300 100" preserveAspectRatio="none">
                <path
                  d="M0,60 Q50,55 75,50 T150,45 Q200,40 250,35 T300,30"
                  fill="none"
                  stroke="hsl(var(--primary))"
                  strokeWidth="2"
                />
                <path
                  d="M0,60 Q50,55 75,50 T150,45 Q200,40 250,35 T300,30 L300,100 L0,100 Z"
                  fill="hsl(var(--primary))"
                  opacity="0.2"
                />
              </svg>
              <div className="absolute bottom-2 left-0 right-0 flex justify-around text-xs text-muted-foreground">
                <span>1</span>
                <span>2</span>
                <span>3</span>
                <span>4</span>
                <span>5</span>
                <span>6</span>
              </div>
            </div>

            {/* Patient Stats */}
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-muted-foreground">
                  <Users className="w-4 h-4" />
                  <span className="text-sm">New Patients</span>
                </div>
                <p className="text-2xl font-bold">200(20%)</p>
              </div>
              <div className="space-y-2">
                <div className="flex items-center gap-2 text-muted-foreground">
                  <CreditCard className="w-4 h-4" />
                  <span className="text-sm">Old Patients</span>
                </div>
                <p className="text-2xl font-bold">800(80%)</p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Recent Arrived */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-lg font-bold">Recent Arrived</h3>
              <p className="text-sm text-muted-foreground">
                List of contact who recently joined
              </p>
            </div>
            <Button variant="ghost" size="sm" className="text-primary">
              See all
            </Button>
          </div>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Avatar className="w-10 h-10 bg-muted">
                    <AvatarFallback className="text-muted-foreground">HK</AvatarFallback>
                  </Avatar>
                  <div>
                    <p className="font-semibold">Hardik Kareliya</p>
                    <p className="text-sm text-muted-foreground">8866388440</p>
                  </div>
                </div>
                <ChevronRight className="w-5 h-5 text-muted-foreground" />
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      <BottomNav variant="clinic" />
    </div>
  );
};

export default Clinic;
