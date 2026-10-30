-- The tables of spec/runs/schema_sql's dump, without the rest of pg_dump's output.

CREATE TABLE public.notes (
    id integer NOT NULL,
    body text NOT NULL,
    seen boolean,
    title character varying(80),
    made timestamp with time zone DEFAULT now()
);
CREATE TABLE public.tags (
    id integer NOT NULL,
    note_id integer,
    label text
);
