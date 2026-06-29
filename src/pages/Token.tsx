import { useState } from "react";
import { Header } from "@/components/Header";
import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Users, Clock, Ticket, Search, Plus, MoreVertical } from "lucide-react";
import { cn } from "@/lib/utils";

const Token = () => {
  const [activeTab, setActiveTab] = useState<"current" | "skipped" | "completed">("current");
  const [canBookNew, setCanBookNew] = useState(true);

  const tabs = [
    { id: "current" as const, label: "Current" },
    { id: "skipped" as const, label: "Skipped" },
    { id: "completed" as const, label: "Completed" },
  ];

  const tokens = [
    { id: 1, name: "Hardik Kareliya", date: "12 Aug 2025 | 08:00 PM", number: 13, initials: "HK" },
    { id: 2, name: "Aryan Chavda", date: "12 Aug 2025 | 08:15 PM", number: 14, initials: "AC" },
  ];

  return (
    <div className="min-h-screen bg-background pb-20">
      <Header userInitials="NA" />

      <div className="p-4 space-y-6">
        {/* Current Token */}
        <Card>
          <CardContent className="p-4">
            <div className="flex items-center justify-between mb-4">
              <div>
                <p className="text-sm text-muted-foreground mb-1">Currently</p>
                <p className="text-3xl font-bold">#12</p>
              </div>
              <div className="text-right">
                <p className="font-semibold">Hardik Kareliya</p>
                <p className="text-xs text-muted-foreground">12 Aug 2025 | 08:00 PM</p>
              </div>
            </div>

            <div className="flex gap-2 mb-4">
              <Button variant="outline" className="flex-1 h-12">
                Skip
              </Button>
              <Button className="flex-1 h-12">Mark Complete</Button>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-3 gap-3">
              <div className="text-center">
                <Users className="w-5 h-5 mx-auto mb-1 text-muted-foreground" />
                <p className="text-xs text-muted-foreground mb-1">in Queue</p>
                <p className="text-2xl font-bold">25</p>
              </div>
              <div className="text-center">
                <Clock className="w-5 h-5 mx-auto mb-1 text-muted-foreground" />
                <p className="text-xs text-muted-foreground mb-1">Est. Time</p>
                <p className="text-2xl font-bold">1h 50m</p>
              </div>
              <div className="text-center">
                <Ticket className="w-5 h-5 mx-auto mb-1 text-muted-foreground" />
                <p className="text-xs text-muted-foreground mb-1">Total Today</p>
                <p className="text-2xl font-bold">50</p>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Can book new token */}
        <Card>
          <CardContent className="p-4 flex items-center justify-between">
            <span className="font-medium">Can book new token?</span>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant={canBookNew ? "default" : "outline"}
                onClick={() => setCanBookNew(true)}
                className="min-w-[60px]"
              >
                Yes
              </Button>
              <Button
                size="sm"
                variant={!canBookNew ? "default" : "outline"}
                onClick={() => setCanBookNew(false)}
                className="min-w-[60px]"
              >
                No
              </Button>
            </div>
          </CardContent>
        </Card>

        {/* Tabs */}
        <div className="flex gap-2">
          {tabs.map((tab) => (
            <Button
              key={tab.id}
              variant={activeTab === tab.id ? "default" : "outline"}
              onClick={() => setActiveTab(tab.id)}
              className="flex-1"
            >
              {tab.label}
            </Button>
          ))}
        </div>

        {/* Search and Add */}
        <div className="flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <Input placeholder="Search" className="pl-10" />
          </div>
          <Button size="icon" className="shrink-0">
            <Plus className="w-5 h-5" />
          </Button>
        </div>

        {/* Token List */}
        <div className="space-y-3">
          {tokens.map((token) => (
            <Card key={token.id}>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <Avatar className="w-10 h-10 bg-muted">
                      <AvatarFallback className="text-muted-foreground">
                        {token.initials}
                      </AvatarFallback>
                    </Avatar>
                    <div>
                      <p className="font-semibold">{token.name}</p>
                      <p className="text-xs text-muted-foreground">{token.date}</p>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <p className="text-xl font-bold">#{token.number}</p>
                    <Button variant="ghost" size="icon">
                      <MoreVertical className="w-5 h-5" />
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>

      <BottomNav variant="clinic" />
    </div>
  );
};

export default Token;
