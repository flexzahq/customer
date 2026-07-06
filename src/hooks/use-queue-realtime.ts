import { useEffect, useRef } from "react";
import { supabase } from "@/lib/supabase";

type Options = {
  doctorId?: string | null;
  enabled?: boolean;
  onChange: () => void;
};

/**
 * Subscribe to token + session changes for one doctor.
 * Falls back to caller’s polling if Realtime is unavailable.
 */
export function useQueueRealtime({
  doctorId,
  enabled = true,
  onChange,
}: Options) {
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;

  useEffect(() => {
    if (!enabled || !doctorId) return;

    const channel = supabase
      .channel(`flexza-queue-${doctorId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "tokens",
          filter: `doctor_id=eq.${doctorId}`,
        },
        () => {
          onChangeRef.current();
        },
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "queue_sessions",
          filter: `doctor_id=eq.${doctorId}`,
        },
        () => {
          onChangeRef.current();
        },
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
  }, [doctorId, enabled]);
}
