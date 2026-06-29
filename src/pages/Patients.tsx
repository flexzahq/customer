import { useState } from "react";
import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Search, Plus, Phone } from "lucide-react";

const Patients = () => {
  const [search, setSearch] = useState("");

  const patients = [
    { id: 1, name: "Hardik Kareliya", phone: "8866388440", initials: "HK" },
    { id: 2, name: "Hardik Kareliya", phone: "8866388440", initials: "HK" },
    { id: 3, name: "Hardik Kareliya", phone: "8866388440", initials: "HK" },
  ];

  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        {/* Header */}
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold">Patients</h1>
          <Button size="icon" className="rounded-full">
            <Plus className="w-5 h-5" />
          </Button>
        </div>

        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-muted-foreground" />
          <Input
            placeholder="Search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-10 h-12"
          />
        </div>

        {/* Patient List */}
        <div className="space-y-3">
          {patients.map((patient) => (
            <Card key={patient.id}>
              <CardContent className="p-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <Avatar className="w-12 h-12 bg-muted">
                      <AvatarFallback className="text-muted-foreground font-semibold">
                        {patient.initials}
                      </AvatarFallback>
                    </Avatar>
                    <div>
                      <p className="font-semibold">{patient.name}</p>
                      <p className="text-sm text-muted-foreground">{patient.phone}</p>
                    </div>
                  </div>
                  <Button variant="ghost" size="icon">
                    <Phone className="w-5 h-5" />
                  </Button>
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

export default Patients;
