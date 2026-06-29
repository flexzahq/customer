import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";

const About = () => {
  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">About</h1>

        <Card>
          <CardContent className="p-6 space-y-4">
            <div>
              <h2 className="text-xl font-bold mb-2">Svedna Clinic</h2>
              <p className="text-muted-foreground">Skin & Wellness Center</p>
            </div>

            <div className="space-y-2">
              <p className="text-sm">
                Welcome to Svedna Clinic, your trusted partner in skin and wellness care.
                We provide comprehensive dermatological services with a focus on patient
                comfort and satisfaction.
              </p>
              <p className="text-sm">
                Our experienced team of professionals is dedicated to helping you achieve
                healthy, glowing skin through personalized treatment plans and cutting-edge
                technology.
              </p>
            </div>

            <div className="pt-4 border-t">
              <h3 className="font-semibold mb-2">Services</h3>
              <ul className="space-y-1 text-sm text-muted-foreground">
                <li>• Dermatology Consultations</li>
                <li>• Skin Treatments</li>
                <li>• Wellness Programs</li>
                <li>• Cosmetic Procedures</li>
              </ul>
            </div>
          </CardContent>
        </Card>
      </div>

      <BottomNav variant="patient" />
    </div>
  );
};

export default About;
