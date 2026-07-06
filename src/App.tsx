import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { I18nProvider } from "@/lib/i18n";
import Entry from "./pages/Entry";
import Login from "./pages/Login";
import Home from "./pages/Home";
import ClinicEntry from "./pages/ClinicEntry";
import Clinic from "./pages/Clinic";
import Token from "./pages/Token";
import Patients from "./pages/Patients";
import Notifications from "./pages/Notifications";
import Timing from "./pages/Timing";
import About from "./pages/About";
import Help from "./pages/Help";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster />
      <Sonner />
      <I18nProvider>
        <BrowserRouter>
          <Routes>
            {/* Patient entry */}
            <Route path="/" element={<Entry />} />
            <Route path="/d/:doctorCode" element={<Home />} />
            <Route path="/d/:doctorCode/timing" element={<Timing />} />
            <Route path="/d/:doctorCode/about" element={<About />} />
            <Route path="/d/:doctorCode/help" element={<Help />} />

            {/* Clinic staff */}
            <Route path="/clinic" element={<ClinicEntry />} />
            <Route path="/clinic/d/:doctorCode" element={<Clinic />} />
            <Route path="/clinic/d/:doctorCode/token" element={<Token />} />
            <Route path="/clinic/d/:doctorCode/patients" element={<Patients />} />
            <Route
              path="/clinic/d/:doctorCode/notifications"
              element={<Notifications />}
            />

            <Route path="/login" element={<Login />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </I18nProvider>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
