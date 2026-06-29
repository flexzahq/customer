import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { User, Phone, Lock, Copy, Check } from "lucide-react";
import { toast } from "sonner";

type LoginStage = "register" | "otp" | "token";

const Login = () => {
  const navigate = useNavigate();
  const [stage, setStage] = useState<LoginStage>("register");
  const [name, setName] = useState("");
  const [mobile, setMobile] = useState("");
  const [otp, setOtp] = useState("");
  const [tokenName, setTokenName] = useState("");
  const [generatedToken, setGeneratedToken] = useState("");
  const [copied, setCopied] = useState(false);

  const generateToken = () => {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let token = "";
    for (let i = 0; i < 32; i++) {
      token += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return token;
  };

  const handleSendOTP = () => {
    if (!name || !mobile) {
      toast.error("Please fill in all fields");
      return;
    }
    if (!/^\d{10}$/.test(mobile.replace(/\D/g, ""))) {
      toast.error("Please enter a valid 10-digit mobile number");
      return;
    }
    toast.success("OTP sent successfully!");
    setStage("otp");
  };

  const handleVerifyOTP = () => {
    if (!otp) {
      toast.error("Please enter OTP");
      return;
    }
    if (otp.length !== 6) {
      toast.error("OTP must be 6 digits");
      return;
    }
    toast.success("OTP verified successfully!");
    setGeneratedToken(generateToken());
    setStage("token");
  };

  const handleSaveToken = () => {
    if (!tokenName.trim()) {
      toast.error("Please enter a name for this token");
      return;
    }
    toast.success("Token saved successfully!");
    setTimeout(() => navigate("/"), 1500);
  };

  const copyToClipboard = () => {
    navigator.clipboard.writeText(generatedToken);
    setCopied(true);
    toast.success("Token copied to clipboard!");
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-4">
      <div className="w-full max-w-md rounded-[12rem] border border-border bg-card/95 p-8 shadow-2xl ring-1 ring-black/5 backdrop-blur-sm transition-all duration-300">
        <div className="text-center space-y-2">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-primary rounded-2xl mb-4">
            <div className="grid grid-cols-2 gap-1">
              <div className="w-3 h-3 bg-primary-foreground rounded-sm" />
              <div className="w-3 h-3 bg-primary-foreground rounded-sm" />
              <div className="w-3 h-3 bg-primary-foreground rounded-sm" />
              <div className="w-3 h-3 bg-primary-foreground rounded-sm" />
            </div>
          </div>
          <h1 className="text-5xl font-bold">Queba</h1>
          <p className="text-2xl font-bold mt-6">
            {stage === "register" && "Register"}
            {stage === "otp" && "Verify OTP"}
            {stage === "token" && "Save Token"}
          </p>
          <p className="text-sm text-muted-foreground">
            {stage === "register" && "Fill below details and do quick login"}
            {stage === "otp" && `Enter OTP sent to ${mobile}`}
            {stage === "token" && "Save this token with a name for future use"}
          </p>
        </div>

        <div className="space-y-4 mt-8">
          {/* Register Stage */}
          {stage === "register" && (
            <>
              <div className="relative">
                <div className="absolute left-0 top-0 bottom-0 w-14 bg-foreground rounded-l-xl flex items-center justify-center">
                  <User className="w-5 h-5 text-background" />
                </div>
                <Input
                  type="text"
                  placeholder="Your name"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  className="pl-16 h-14 rounded-xl bg-input border-0"
                />
              </div>

              <div className="relative">
                <div className="absolute left-0 top-0 bottom-0 w-14 bg-foreground rounded-l-xl flex items-center justify-center">
                  <Phone className="w-5 h-5 text-background" />
                </div>
                <Input
                  type="tel"
                  placeholder="Mobile Number"
                  value={mobile}
                  onChange={(e) => setMobile(e.target.value)}
                  className="pl-16 h-14 rounded-xl bg-input border-0"
                />
              </div>

              <Button
                onClick={handleSendOTP}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                Send OTP
              </Button>
            </>
          )}

          {/* OTP Verification Stage */}
          {stage === "otp" && (
            <>
              <div className="relative">
                <div className="absolute left-0 top-0 bottom-0 w-14 bg-foreground rounded-l-xl flex items-center justify-center">
                  <Lock className="w-5 h-5 text-background" />
                </div>
                <Input
                  type="text"
                  placeholder="Enter 6-digit OTP"
                  value={otp}
                  onChange={(e) =>
                    setOtp(e.target.value.replace(/\D/g, "").slice(0, 6))
                  }
                  maxLength="6"
                  className="pl-16 h-14 rounded-xl bg-input border-0 tracking-widest text-center text-lg"
                />
              </div>

              <Button
                onClick={handleVerifyOTP}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                Verify OTP
              </Button>

              <Button
                onClick={() => {
                  setStage("register");
                  setOtp("");
                }}
                variant="outline"
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                Back
              </Button>
            </>
          )}

          {/* Token Save Stage */}
          {stage === "token" && (
            <>
              <div className="relative">
                <div className="absolute left-0 top-0 bottom-0 w-14 bg-foreground rounded-l-xl flex items-center justify-center">
                  <Lock className="w-5 h-5 text-background" />
                </div>
                <Input
                  type="text"
                  placeholder="Token name (e.g., 'My Device')"
                  value={tokenName}
                  onChange={(e) => setTokenName(e.target.value)}
                  className="pl-16 h-14 rounded-xl bg-input border-0"
                />
              </div>

              <div className="bg-muted/50 rounded-xl p-4 border border-border/50">
                <p className="text-xs text-muted-foreground mb-2">Your Token:</p>
                <div className="flex items-center gap-2">
                  <code className="flex-1 text-xs break-all font-mono text-foreground">
                    {generatedToken}
                  </code>
                  <button
                    onClick={copyToClipboard}
                    className="flex-shrink-0 p-2 hover:bg-background rounded-lg transition-colors"
                    title="Copy token"
                  >
                    {copied ? (
                      <Check className="w-4 h-4 text-green-500" />
                    ) : (
                      <Copy className="w-4 h-4 text-muted-foreground" />
                    )}
                  </button>
                </div>
              </div>

              <Button
                onClick={handleSaveToken}
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                Save Token & Continue
              </Button>

              <Button
                onClick={() => setStage("otp")}
                variant="outline"
                className="w-full h-14 text-base font-semibold rounded-xl"
              >
                Back
              </Button>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default Login;
