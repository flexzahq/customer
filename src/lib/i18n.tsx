import { createContext, useContext, useMemo, useState, type ReactNode } from "react";

export type Language = "en" | "gu";

export const TRANSLATIONS = {
  en: {
    clinicName: "Svedna Clinic",
    subtitle: "Skin & Wellness Center",
    noQueueTitle: "No Queue",
    noQueueDesc: "Book now & get your turn quickly",
    recentHistory: "Recent History",
    seeAll: "See all",
    pastHistoryDesc: "You can see past history below.",
    loginNow: "Login Now",
    fillQuickLogin: "Fill below details and do quick login",
    enterMobilePlaceholder: "Enter mobile number",
    sendOtp: "Send OTP",
    verify: "Verify",
    yourNamePlaceholder: "Your name",
    didntReceiveOtp: "Didn't receive OTP?",
    resendTimer: "30sec",
    weSentOtp: "We sent OTP",
    checkOtpOn: "Check 4 digit OTP on",
    enterOtp: "Enter the 4-digit OTP",
    otpSent: "OTP sent",
    useDummyOtp: "Use OTP",
    yourToken: "Your Token",
    tokenAllocated: "Your token has been allocated!",
    yourTokenNumberAllocated: "Here is your assigned token number.",
    yourName: "Your name",
    enterNameSub: "We'll use this to personalise your experience",
    backToHome: "Back to Home",
    editMobile: "Edit mobile",
    resendOtp: "Resend OTP",
    enterValidMobile: "Enter a valid 10-digit mobile number",
    navHome: "Home",
    navTiming: "Timing",
    navAbout: "About",
    navHelp: "Help",
    navToken: "Token",
    navNotification: "Notification",
    navPatients: "Patients",
    bookMyToken: "Book My Token",
    currently: "Currently",
    queue: "Queue",
    nameSaved: "Name is avaiable",
    save: "Save",
    skip: "Skip",
  },
  gu: {
    clinicName: "સ્વેદના ક્લિનિક",
    subtitle: "ચામડી અને વેલનેસ સેન્ટર",
    noQueueTitle: "કોઈ કતાર નથી",
    noQueueDesc: "હવે બુક કરો અને તમારા વારમાં ઝડપથી મેળવો",
    recentHistory: "તાજેતરનો ઇતિહાસ",
    seeAll: "બધા જુઓ",
    pastHistoryDesc: "તમે નીચે પાછલા ઇતિહાસ જોઈ શકો છો.",
    loginNow: "લૉગિન કરો",
    fillQuickLogin: "નીચેની વિગતો ભરો અને ઝડપી લૉગિન કરો",
    enterMobilePlaceholder: "મોબાઇલ નંબર દાખલ કરો",
    sendOtp: "OTP મોકલો",
    verify: "સত্যાપિત કરો",
    yourNamePlaceholder: "તમારું નામ",
    didntReceiveOtp: "OTP મળ્યું નહી?",
    resendTimer: "30સેક",
    weSentOtp: "અમે OTP મોકલ્યો",
    checkOtpOn: "એસ 4 અંકોનો OTP તપાસો",
    enterOtp: "4 અંકોનો OTP દાખલ કરો",
    otpSent: "OTP મોકલાવ્યો",
    useDummyOtp: "OTP ઉપયોગ કરો",
    yourToken: "તમારો ટોકન",
    tokenAllocated: "તમારો ટોકન અપાયો છે!",
    yourTokenNumberAllocated: "અહીં તમારો ફાળવાયેલ ટોકન નંબર છે.",
    yourName: "તમારું નામ",
    enterNameSub: "અમે તમારા અનુભવને વ્યક્તિગત બનાવવા માટે આનો ઉપયોગ કરીશું",
    backToHome: "હોમ પર પાછા જાવો",
    editMobile: "મોબાઇલ સંપાદિત કરો",
    resendOtp: "OTP ફરીથી મોકલો",
    enterValidMobile: "કૃપા કરી 10 અંકનો માન્ય મોબાઇલ નંબર દાખલ કરો",
    navHome: "હોમ",
    navTiming: "સમય",
    navAbout: "વિશે",
    navHelp: "મદદ",
    navToken: "ટોકન",
    navNotification: "સૂચના",
    navPatients: "આરસોગીઓ",
    bookMyToken: "મારો ટોકન બુક કરો",
    currently: "પ્રાપ્તમાન",
    queue: "કતાર",
  },
} as const;

export type TranslationKey = keyof typeof TRANSLATIONS["en"];

interface I18nContextValue {
  lang: Language;
  setLang: (lang: Language) => void;
  t: (key: TranslationKey) => string;
}

const I18nContext = createContext<I18nContextValue | undefined>(undefined);

type I18nProviderProps = {
  children?: ReactNode;
};

export const I18nProvider = ({ children }: I18nProviderProps) => {
  const [lang, setLang] = useState<Language>("en");

  const t = useMemo(
    () => (key: TranslationKey) => TRANSLATIONS[lang][key],
    [lang],
  );

  return (
    <I18nContext.Provider value={{ lang, setLang, t }}>
      {children}
    </I18nContext.Provider>
  );
};

export const useI18n = () => {
  const context = useContext(I18nContext);
  if (!context) {
    throw new Error("useI18n must be used within I18nProvider");
  }
  return context;
};
