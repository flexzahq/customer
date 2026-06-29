import { BottomNav } from "@/components/BottomNav";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Phone, Mail, MessageCircle } from "lucide-react";

const Help = () => {
  return (
    <div className="min-h-screen bg-background pb-20">
      <div className="p-4 space-y-6">
        <h1 className="text-2xl font-bold">Help & Support</h1>

        <div className="space-y-4">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center">
                  <Phone className="w-6 h-6 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold">Call Us</p>
                  <p className="text-sm text-muted-foreground">+91 98765 43210</p>
                </div>
                <Button variant="outline" size="sm">Call</Button>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center">
                  <Mail className="w-6 h-6 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold">Email Us</p>
                  <p className="text-sm text-muted-foreground">support@svedna.com</p>
                </div>
                <Button variant="outline" size="sm">Email</Button>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 bg-primary/10 rounded-full flex items-center justify-center">
                  <MessageCircle className="w-6 h-6 text-primary" />
                </div>
                <div className="flex-1">
                  <p className="font-semibold">Live Chat</p>
                  <p className="text-sm text-muted-foreground">Chat with our support team</p>
                </div>
                <Button variant="outline" size="sm">Chat</Button>
              </div>
            </CardContent>
          </Card>
        </div>

        <div className="pt-6">
          <h2 className="text-lg font-bold mb-4">Frequently Asked Questions</h2>
          <div className="space-y-3">
            <Card>
              <CardContent className="p-4">
                <p className="font-semibold mb-2">How do I book a token?</p>
                <p className="text-sm text-muted-foreground">
                  Simply tap on "Book My Token" button on the home screen and follow the instructions.
                </p>
              </CardContent>
            </Card>
            <Card>
              <CardContent className="p-4">
                <p className="font-semibold mb-2">Can I cancel my token?</p>
                <p className="text-sm text-muted-foreground">
                  Yes, you can cancel your token from the Recent History section before your turn.
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      <BottomNav variant="patient" />
    </div>
  );
};

export default Help;
