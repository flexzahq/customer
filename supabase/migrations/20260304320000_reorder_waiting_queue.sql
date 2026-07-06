-- Reorder waiting tokens in today's queue session (vendor panel drag-and-drop)

CREATE OR REPLACE FUNCTION public.reorder_waiting_tokens(
  p_session_id uuid,
  p_ordered_token_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.queue_sessions;
  v_waiting_ids uuid[];
  v_waiting_numbers int[];
  v_offset int := 1000000;
  i int;
BEGIN
  IF p_ordered_token_ids IS NULL OR array_length(p_ordered_token_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'invalid_reorder' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_session
  FROM public.queue_sessions
  WHERE id = p_session_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'session_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_session.session_date <> public.flexza_today() THEN
    RAISE EXCEPTION 'session_not_today' USING ERRCODE = '22023';
  END IF;

  -- Lock waiting rows (FOR UPDATE cannot be used with array_agg).
  PERFORM 1
  FROM public.tokens t
  WHERE t.session_id = p_session_id
    AND t.status = 'waiting'
  FOR UPDATE;

  SELECT
    coalesce(array_agg(t.id ORDER BY t.number), '{}'::uuid[]),
    coalesce(array_agg(t.number ORDER BY t.number), '{}'::int[])
  INTO v_waiting_ids, v_waiting_numbers
  FROM public.tokens t
  WHERE t.session_id = p_session_id
    AND t.status = 'waiting';

  IF array_length(v_waiting_ids, 1) IS DISTINCT FROM array_length(p_ordered_token_ids, 1) THEN
    RAISE EXCEPTION 'invalid_reorder' USING ERRCODE = '22023';
  END IF;

  IF NOT (
    SELECT bool_and(id = ANY (v_waiting_ids))
    FROM unnest(p_ordered_token_ids) AS id
  ) THEN
    RAISE EXCEPTION 'invalid_reorder' USING ERRCODE = '22023';
  END IF;

  -- Avoid unique (session_id, number) conflicts while permuting.
  UPDATE public.tokens
  SET number = number + v_offset
  WHERE session_id = p_session_id
    AND status = 'waiting';

  FOR i IN 1..array_length(p_ordered_token_ids, 1) LOOP
    UPDATE public.tokens
    SET number = v_waiting_numbers[i]
    WHERE id = p_ordered_token_ids[i]
      AND session_id = p_session_id
      AND status = 'waiting';
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'session_id', p_session_id,
    'waiting_count', array_length(p_ordered_token_ids, 1)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.reorder_waiting_tokens(uuid, uuid[]) TO anon, authenticated;
