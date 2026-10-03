-- Scenario 2: Computer Laboratory Reservations

DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;
DROP PROCEDURE IF EXISTS reserve_workstations(INT, VARCHAR, INT);
DROP PROCEDURE IF EXISTS cancel_reservation(INT);

-- 1. Tables and sample data
CREATE TABLE lab_sessions (
    session_id               SERIAL PRIMARY KEY,
    session_name             VARCHAR(100) NOT NULL,
    available_workstations   INT NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id       SERIAL PRIMARY KEY,
    session_id           INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer             VARCHAR(100) NOT NULL,
    workstations_reserved INT NOT NULL CHECK (workstations_reserved > 0),
    status               VARCHAR(10) NOT NULL DEFAULT 'RESERVED'
                         CHECK (status IN ('RESERVED', 'CANCELLED'))
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab', 30),
    ('Tuesday 10:00 - Databases Lab', 8),
    ('Wednesday 14:00 - Networking Lab', 0);

SELECT * FROM lab_sessions ORDER BY session_id;

-- 2. IF / ELSIF / ELSE: session capacity report
DO $$
DECLARE
    rec    RECORD;
    status TEXT;
BEGIN
    FOR rec IN SELECT session_name, available_workstations
               FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            status := 'FULL';
        ELSIF rec.available_workstations <= 10 THEN
            status := 'NEARLY FULL';
        ELSE
            status := 'has enough workstations';
        END IF;
        RAISE NOTICE '% (% free): %', rec.session_name, rec.available_workstations, status;
    END LOOP;
END $$;

-- 3. WHILE loop and numeric FOR loop
DO $$
DECLARE
    n INT := 1;
BEGIN
    WHILE n <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', n;
        n := n + 1;
    END LOOP;

    FOR i IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', i;
    END LOOP;
END $$;

-- 4. reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT, p_lecturer VARCHAR, p_quantity INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_quantity;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available',
            p_lecturer, p_quantity, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_quantity
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations_reserved, status)
    VALUES (p_session_id, p_lecturer, p_quantity, 'RESERVED');

    RAISE NOTICE 'Reservation recorded for %: % workstation(s) in session %',
        p_lecturer, p_quantity, p_session_id;
END $$;

-- 5. Two valid reservations and one exceeding capacity
CALL reserve_workstations(1, 'Dr. Banda', 10);   -- valid
CALL reserve_workstations(2, 'Mr. Phiri', 3);    -- valid
CALL reserve_workstations(2, 'Ms. Tembo', 20);   -- exceeds capacity (rejected)

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation procedure
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_quantity   INT;
    v_status     VARCHAR;
BEGIN
    SELECT session_id, workstations_reserved, status
    INTO v_session_id, v_quantity, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Reservation % does not exist', p_reservation_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled; nothing released', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_quantity
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled; % workstation(s) released',
        p_reservation_id, v_quantity;
END $$;

CALL cancel_reservation(1);   -- releases workstations
CALL cancel_reservation(1);   -- second call must not release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 7. Explicit cursor: sessions with few workstations remaining (10 or fewer)
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 10 ORDER BY available_workstations;
    v_name lab_sessions.session_name%TYPE;
    v_free lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_free;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: % - % free', v_name, v_free;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Request zero workstations: handled with an EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Mulenga', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;