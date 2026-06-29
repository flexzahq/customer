import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { I18nProvider } from "@/lib/i18n";
import Login from "./pages/Login";
import Home from "./pages/Home";
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
            <Route path="/login" element={<Login />} />
          <Route path="/" element={<Home />} />
          <Route path="/clinic" element={<Clinic />} />
          <Route path="/token" element={<Token />} />
          <Route path="/patients" element={<Patients />} />
          <Route path="/notifications" element={<Notifications />} />
          <Route path="/timing" element={<Timing />} />
          <Route path="/about" element={<About />} />
          <Route path="/help" element={<Help />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </BrowserRouter>
    </I18nProvider>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
