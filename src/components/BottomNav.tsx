import { useState } from "react";
import { Home, Clock, Info, HelpCircle, Ticket, Bell, Users } from "lucide-react";
import { Link, useLocation } from "react-router-dom";
import { cn } from "@/lib/utils";
import { TimingDrawer } from "./TimingDrawer";
import { useI18n, type TranslationKey } from "@/lib/i18n";
import { useClinicProfile } from "@/lib/clinicProfile";

interface NavItem {
  icon: React.ElementType;
  labelKey: TranslationKey;
  path: string;
  isDrawer?: boolean;
}

interface BottomNavProps {
  variant?: "patient" | "clinic";
  basePath?: string;
  /** Patient nav: loads live timings for drawer */
  doctorCode?: string;
}

export const BottomNav = ({
  variant = "patient",
  basePath = "",
  doctorCode = "",
}: BottomNavProps) => {
  const location = useLocation();
  const [showTiming, setShowTiming] = useState(false);
  const { t } = useI18n();
  const profileQuery = useClinicProfile(doctorCode);

  const patientNavItems: NavItem[] = [
    { icon: Home, labelKey: "navHome", path: basePath || "/" },
    { icon: Clock, labelKey: "navTiming", path: `${basePath}/timing`, isDrawer: true },
    { icon: Info, labelKey: "navAbout", path: `${basePath}/about` },
    { icon: HelpCircle, labelKey: "navHelp", path: `${basePath}/help` },
  ];

  const clinicNavItems: NavItem[] = [
    { icon: Home, labelKey: "navHome", path: basePath || "/clinic" },
    { icon: Ticket, labelKey: "navToken", path: `${basePath}/token` },
    { icon: Bell, labelKey: "navNotification", path: `${basePath}/notifications` },
    { icon: Users, labelKey: "navPatients", path: `${basePath}/patients` },
  ];

  const items = variant === "patient" ? patientNavItems : clinicNavItems;

  return (
    <>
      <nav className="fixed bottom-0 left-0 right-0 bg-card border-t border-border">
        <div className="flex items-center justify-around h-16 max-w-lg mx-auto">
          {items.map((item) => {
            const Icon = item.icon;
            const isActive = location.pathname === item.path;

            if (item.isDrawer) {
              return (
                <button
                  key={item.path}
                  onClick={() => setShowTiming(true)}
                  className={cn(
                    "flex flex-col items-center justify-center gap-1 px-4 py-2 transition-colors",
                    isActive ? "text-primary" : "text-muted-foreground",
                  )}
                >
                  <Icon className="w-6 h-6" />
                  <span className="text-xs font-medium">{t(item.labelKey)}</span>
                </button>
              );
            }

            return (
              <Link
                key={item.path}
                to={item.path}
                className={cn(
                  "flex flex-col items-center justify-center gap-1 px-4 py-2 transition-colors",
                  isActive ? "text-primary" : "text-muted-foreground",
                )}
              >
                <Icon className="w-6 h-6" />
                <span className="text-xs font-medium">{t(item.labelKey)}</span>
              </Link>
            );
          })}
        </div>
      </nav>

      {variant === "patient" && (
        <TimingDrawer
          open={showTiming}
          onOpenChange={setShowTiming}
          morningStart={profileQuery.data?.morningStart}
          morningEnd={profileQuery.data?.morningEnd}
          eveningStart={profileQuery.data?.eveningStart}
          eveningEnd={profileQuery.data?.eveningEnd}
          loading={profileQuery.isLoading}
        />
      )}
    </>
  );
};
