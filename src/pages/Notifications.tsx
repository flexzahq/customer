import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Ticket } from "lucide-react";

const Notifications = () => {
  const notifications = [
    { id: 1, token: 12, bookedBy: "Aryan Chavada", date: "Tue, 15 Oct 2025 | 01:00PM" },
    { id: 2, token: 12, bookedBy: "Aryan Chavada", date: "Tue, 15 Oct 2025 | 01:00PM" },
    { id: 3, token: 12, bookedBy: "Aryan Chavada", date: "Tue, 15 Oct 2025 | 01:00PM" },
  ];

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">Notifications</h1>

        <div className="space-y-3">
          {notifications.map((notification) => (
            <Card key={notification.id}>
              <CardContent className="p-4">
                <div className="flex gap-3">
                  <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center shrink-0">
                    <Ticket className="w-5 h-5 text-primary" />
                  </div>
                  <div className="flex-1">
                    <p className="font-medium">
                      Token <span className="font-bold">#{notification.token}</span> booked by{" "}
                      <span className="font-bold">{notification.bookedBy}</span>
                    </p>
                    <p className="text-sm text-muted-foreground mt-1">
                      {notification.date}
                    </p>
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

export default Notifications;
